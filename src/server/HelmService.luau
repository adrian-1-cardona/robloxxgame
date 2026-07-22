-- Helm: lock a sailor standing at the wheel, steer by look, drive with throttle
-- (W/S · stick · mobile arrows). Jump / B unlocks. Idle throttle = drift stop.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local StarterBaseService = require(script.Parent:WaitForChild("StarterBaseService"))
local IslandService = require(script.Parent:WaitForChild("IslandService"))

export type HelmSession = {
	userId: number,
	code: string,
	lookFlat: Vector3,
	-- -1..1 — forward along look, reverse opposite; 0 = hold still
	throttle: number,
	wheelSpin: number,
	savedWalkSpeed: number,
	savedJumpHeight: number,
	savedAutoRotate: boolean,
	lockToastAt: number,
	groundToastAt: number,
	connections: { RBXScriptConnection },
}

local HelmService = {}

HelmService._sessionsByUserId = {} :: { [number]: HelmSession }
HelmService._helmsmanByCode = {} :: { [string]: number }
HelmService._HelmState = nil :: RemoteEvent?
HelmService._Toast = nil :: RemoteEvent?
HelmService._getPartyCode = nil :: ((Player) -> string?)?
HelmService._getPartyMembers = nil :: ((string) -> { number })?

local function getHelmStand(code: string): BasePart?
	local model = StarterBaseService.getBaseModel(code)
	if not model then
		return nil
	end
	local kit = model:FindFirstChild("StarterKit")
	local stand = kit and kit:FindFirstChild("HelmStand")
	if stand and stand:IsA("BasePart") then
		return stand
	end
	return nil
end

local function getHelmPrompt(code: string): ProximityPrompt?
	local model = StarterBaseService.getBaseModel(code)
	if not model then
		return nil
	end
	local kit = model:FindFirstChild("StarterKit")
	local anchor = kit and kit:FindFirstChild("HelmPromptAnchor")
	local prompt = anchor and anchor:FindFirstChild("HelmPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		return prompt
	end
	return nil
end

local function getHelmWheel(code: string): (Model?, BasePart?, CFrameValue?)
	local model = StarterBaseService.getBaseModel(code)
	if not model then
		return nil, nil, nil
	end
	local kit = model:FindFirstChild("StarterKit")
	local wheel = kit and kit:FindFirstChild("HelmWheel")
	local column = kit and kit:FindFirstChild("HelmPedestal")
	local restLocal = wheel and wheel:FindFirstChild("WheelRestLocal")
	if
		wheel
		and wheel:IsA("Model")
		and column
		and column:IsA("BasePart")
		and restLocal
		and restLocal:IsA("CFrameValue")
	then
		return wheel, column, restLocal
	end
	return nil, nil, nil
end

local function flattenLook(look: Vector3): Vector3?
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then
		return nil
	end
	return flat.Unit
end

-- Signed yaw from raft heading → look (matches the helmsman face turn)
local function lookYawError(deckForward: Vector3, look: Vector3): number
	return math.atan2(deckForward:Cross(look).Y, deckForward:Dot(look))
end

local function applyWheelSpin(code: string, spinRadians: number)
	local wheel, column, restLocal = getHelmWheel(code)
	if not (wheel and column and restLocal) then
		return
	end
	-- Cylinder axle is local X of the rest pose — spin around that axis
	wheel:PivotTo(column.CFrame * restLocal.Value * CFrame.Angles(spinRadians, 0, 0))
end

local function fireState(player: Player, active: boolean)
	if HelmService._HelmState then
		HelmService._HelmState:FireClient(player, active)
	end
end

local function toast(player: Player, message: string, kind: string)
	if HelmService._Toast then
		HelmService._Toast:FireClient(player, message, kind)
	end
end

function HelmService.release(player: Player, reason: string?)
	local session = HelmService._sessionsByUserId[player.UserId]
	if not session then
		return
	end

	HelmService._sessionsByUserId[player.UserId] = nil
	if HelmService._helmsmanByCode[session.code] == player.UserId then
		HelmService._helmsmanByCode[session.code] = nil
	end

	for _, conn in session.connections do
		conn:Disconnect()
	end

	local prompt = getHelmPrompt(session.code)
	if prompt then
		prompt.Enabled = true
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid then
		humanoid.WalkSpeed = session.savedWalkSpeed
		humanoid.JumpHeight = session.savedJumpHeight
		humanoid.AutoRotate = session.savedAutoRotate
		humanoid.PlatformStand = false
	end

	-- Hop off the wheel so the sailor clears the stand lock
	local stand = getHelmStand(session.code)
	if root and root:IsA("BasePart") then
		if stand then
			local hopCf = stand.CFrame * CFrame.new(0, 3.2, 2.5)
			root.CFrame = hopCf
		end
		root.AssemblyLinearVelocity = Vector3.new(0, 42, 0)
		root.AssemblyAngularVelocity = Vector3.zero
	end

	-- Ease the wooden wheel back to rest when leaving the helm
	session.wheelSpin = 0
	applyWheelSpin(session.code, 0)

	fireState(player, false)
	if reason then
		toast(player, reason, "info")
	end
end

function HelmService.mount(player: Player, code: string): boolean
	if HelmService._sessionsByUserId[player.UserId] then
		return false
	end
	if HelmService._helmsmanByCode[code] then
		toast(player, "Someone is already at the wheel.", "error")
		return false
	end

	local partyCode = HelmService._getPartyCode and HelmService._getPartyCode(player)
	if partyCode ~= code then
		toast(player, "That's not your crew's raft.", "error")
		return false
	end

	local stand = getHelmStand(code)
	if not stand then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		return false
	end
	if humanoid.Health <= 0 then
		return false
	end

	local prompt = getHelmPrompt(code)
	if prompt then
		prompt.Enabled = false
	end

	local session: HelmSession = {
		userId = player.UserId,
		code = code,
		lookFlat = flattenLook(stand.CFrame.LookVector) or Vector3.new(0, 0, -1),
		throttle = 0,
		wheelSpin = 0,
		savedWalkSpeed = humanoid.WalkSpeed,
		savedJumpHeight = humanoid.JumpHeight,
		savedAutoRotate = humanoid.AutoRotate,
		lockToastAt = 0,
		groundToastAt = 0,
		connections = {},
	}

	-- Lock standing: no walk, keep jump so they can hop off
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	humanoid.Sit = false
	humanoid.PlatformStand = false
	-- Ensure jump is available to exit
	if humanoid.JumpHeight < 7.2 then
		humanoid.JumpHeight = 7.2
	end

	-- Snap into the stand pose (upright, facing the wheel / bow)
	local standCf = stand.CFrame * CFrame.new(0, 3, 0)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = standCf

	HelmService._sessionsByUserId[player.UserId] = session
	HelmService._helmsmanByCode[code] = player.UserId

	table.insert(
		session.connections,
		humanoid.StateChanged:Connect(function(_old, newState)
			-- Backup unlock if JumpRequest remote is late; ignore Freefall (snap can trip it)
			if newState == Enum.HumanoidStateType.Jumping then
				HelmService.release(player, "Left the helm.")
			end
		end)
	)

	table.insert(
		session.connections,
		humanoid.Died:Connect(function()
			HelmService.release(player)
		end)
	)

	table.insert(
		session.connections,
		player.CharacterRemoving:Connect(function()
			HelmService.release(player)
		end)
	)

	fireState(player, true)
	toast(player, "At the helm — look to steer, W/S to sail the isles, jump / B to leave.", "success")
	return true
end

function HelmService.setLook(player: Player, look: Vector3)
	local session = HelmService._sessionsByUserId[player.UserId]
	if not session then
		return
	end
	local flat = flattenLook(look)
	if flat then
		session.lookFlat = flat
	end
end

function HelmService.setThrottle(player: Player, throttle: number)
	local session = HelmService._sessionsByUserId[player.UserId]
	if not session then
		return
	end
	if typeof(throttle) ~= "number" or throttle ~= throttle then
		return
	end
	session.throttle = math.clamp(throttle, -1, 1)
end

function HelmService.isHelming(player: Player): boolean
	return HelmService._sessionsByUserId[player.UserId] ~= nil
end

local function moveCrewWithDelta(code: string, delta: CFrame, helmsmanUserId: number?)
	if not HelmService._getPartyMembers then
		return
	end
	for _, userId in HelmService._getPartyMembers(code) do
		local plr = Players:GetPlayerByUserId(userId)
		if not plr then
			continue
		end
		-- Helmsman is re-snapped to the stand each frame
		if helmsmanUserId and userId == helmsmanUserId then
			continue
		end
		local character = plr.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.CFrame = delta * root.CFrame
		end
	end
end

local function snapHelmsmanToStand(session: HelmSession)
	local stand = getHelmStand(session.code)
	if not stand then
		return
	end
	local player = Players:GetPlayerByUserId(session.userId)
	if not player then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid) then
		return
	end

	-- Face the way we're sailing; stay planted on the stand
	local face = session.lookFlat
	local pos = (stand.CFrame * CFrame.new(0, 3, 0)).Position
	root.CFrame = CFrame.new(pos, pos + face)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	humanoid.WalkSpeed = 0
	humanoid.Sit = false
end

function HelmService.start(
	helmStateRemote: RemoteEvent,
	toastRemote: RemoteEvent,
	getPartyCode: (Player) -> string?,
	getPartyMembers: (string) -> { number }
)
	HelmService._HelmState = helmStateRemote
	HelmService._Toast = toastRemote
	HelmService._getPartyCode = getPartyCode
	HelmService._getPartyMembers = getPartyMembers

	RunService.Heartbeat:Connect(function(dt)
		for code, userId in HelmService._helmsmanByCode do
			local session = HelmService._sessionsByUserId[userId]
			if not session then
				HelmService._helmsmanByCode[code] = nil
				continue
			end

			local model = StarterBaseService.getBaseModel(code)
			local deck = model and (model.PrimaryPart or model:FindFirstChild("Deck"))
			if not (deck and deck:IsA("BasePart")) then
				continue
			end

			local look = session.lookFlat
			local throttle = session.throttle
			-- Treat near-zero stick noise as stop so idle stays planted
			if math.abs(throttle) < 0.04 then
				throttle = 0
			end
			local speed = Config.Helm.SpeedStudsPerSecond
			-- Positive throttle sails along look; negative reverses while still facing look
			local move = look * (speed * throttle * dt)

			local oldCf = deck.CFrame
			local desiredPos = Vector3.new(
				oldCf.Position.X + move.X,
				oldCf.Position.Y,
				oldCf.Position.Z + move.Z
			)
			-- Visit lockout: once a crew leaves an isle far enough away, the raft can't sail back
			local newPos, blockedIsle = IslandService.clampRaftPosition(session.code, oldCf.Position, desiredPos)
			if blockedIsle and throttle ~= 0 then
				local now = os.clock()
				if now - session.lockToastAt > 2.5 then
					session.lockToastAt = now
					local helmsman = Players:GetPlayerByUserId(userId)
					if helmsman then
						toast(helmsman, `{blockedIsle} won't take you back.`, "error")
					end
				end
			end

			-- Solid shoreline: you can't drive onto an isle. Sailing into one runs the raft
			-- aground and stops it at the beach; steer away to peel off.
			local groundedIsle
			newPos, groundedIsle = IslandService.collideRaft(oldCf.Position, newPos)
			if groundedIsle and throttle ~= 0 then
				local now = os.clock()
				if now - session.groundToastAt > 2.5 then
					session.groundToastAt = now
					local helmsman = Players:GetPlayerByUserId(userId)
					if helmsman then
						toast(helmsman, `Ran aground on {groundedIsle} — steer away.`, "error")
					end
				end
			end
			-- Keep deck level; yaw toward look (steer), not velocity (so reverse faces forward)
			local targetCf = CFrame.lookAt(newPos, newPos + look)
			local alpha = math.clamp(Config.Helm.TurnLerp * dt, 0, 1)
			local lerped = oldCf:Lerp(targetCf, alpha)
			local flatLook = flattenLook(lerped.LookVector) or look
			local newCf = CFrame.lookAt(
				Vector3.new(lerped.Position.X, oldCf.Position.Y, lerped.Position.Z),
				Vector3.new(lerped.Position.X, oldCf.Position.Y, lerped.Position.Z) + flatLook
			)

			if StarterBaseService.setBaseCFrame(code, newCf) then
				local delta = newCf * oldCf:Inverse()
				moveCrewWithDelta(code, delta, userId)
			end

			snapHelmsmanToStand(session)

			-- Spin the wooden wheel with look yaw (same cue as the helmsman facing turn)
			local deckForward = flattenLook(newCf.LookVector) or look
			local yawErr = lookYawError(deckForward, look)
			local targetSpin = math.clamp(
				yawErr * Config.Helm.WheelLookGain,
				-Config.Helm.WheelMaxRadians,
				Config.Helm.WheelMaxRadians
			)
			local spinAlpha = math.clamp(Config.Helm.WheelSpinLerp * dt, 0, 1)
			session.wheelSpin += (targetSpin - session.wheelSpin) * spinAlpha
			applyWheelSpin(code, session.wheelSpin)
		end
	end)
end

function HelmService.bindBase(code: string, model: Model)
	local kit = model:FindFirstChild("StarterKit")
	local anchor = kit and kit:FindFirstChild("HelmPromptAnchor")
	local prompt = anchor and anchor:FindFirstChild("HelmPrompt")
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		return
	end

	prompt.Triggered:Connect(function(player: Player)
		HelmService.mount(player, code)
	end)
end

function HelmService.releaseIfHelming(player: Player)
	if HelmService._sessionsByUserId[player.UserId] then
		HelmService.release(player)
	end
end

function HelmService.onBaseDestroyed(code: string)
	local userId = HelmService._helmsmanByCode[code]
	if not userId then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		HelmService.release(player)
	else
		HelmService._helmsmanByCode[code] = nil
		HelmService._sessionsByUserId[userId] = nil
	end
end

return HelmService
