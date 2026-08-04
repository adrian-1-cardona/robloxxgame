-- Manages pirate ships and crews that spawn at night to hunt player crews.
-- Pirates spawn on ships around player rafts, attack players on boats during nighttime,
-- and despawn at dawn. Includes ship AI, combat coordination, and performance optimization.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DayNight = require(Shared:WaitForChild("DayNight"))

local StarterBaseService = require(script.Parent:WaitForChild("StarterBaseService"))
local PirateShipFactory = require(script.Parent:WaitForChild("Items"):WaitForChild("PirateShipFactory"))
local NpcFactory = require(script.Parent:WaitForChild("Items"):WaitForChild("NpcFactory"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))

export type PirateShip = {
	model: Model,
	id: string,
	crew: { PirateNpc },
	targetCrewCode: string?,
	lastTargetPos: Vector3?,
	spawnTime: number,
	state: "hunting" | "attacking" | "retreating" | "patrolling",
	health: number,
	maxHealth: number,
}

export type PirateNpc = {
	model: Model,
	humanoid: Humanoid,
	shipId: string,
	state: "onShip" | "boarding" | "fighting" | "dead" | "neutral",
	targetPlayer: Player?,
	lastAttackTime: number,
	homePosition: Vector3, -- Position on ship
	weapon: "cutlass" | "pistol",
	isHostile: boolean, -- Whether this pirate is actively hostile
	wasAttacked: boolean, -- Whether this pirate has been attacked by players
}

local PirateService = {}

PirateService._ships = {} :: { [string]: PirateShip }
PirateService._npcs = {} :: { [string]: PirateNpc }
PirateService._lastSpawnCheck = 0
PirateService._updateAccumulator = 0
PirateService._Toast = nil :: RemoteEvent?
PirateService._getPartyCode = nil :: ((Player) -> string?)?
PirateService._getMemberUserIds = nil :: ((string) -> { number })?
PirateService._started = false

-- Configuration
local MAX_SHIPS_PER_CREW = 2 -- Restored for proper nighttime pirate pressure
local MAX_TOTAL_SHIPS = 6 -- Keep reduced for performance but allow more pirate activity
local SPAWN_CHECK_INTERVAL = 6 -- seconds (balanced spawn timing)
local SHIP_SPAWN_DISTANCE = 200 -- studs from player raft
local SHIP_DESPAWN_DISTANCE = 400 -- studs - ships despawn if too far
local ATTACK_RANGE = 150 -- studs - ships start attacking in this range
local PIRATE_SPAWN_CHANCE = 0.65 -- 65% chance per spawn check during night - active but not overwhelming
local UPDATE_FREQUENCY = 0.15 -- seconds between AI updates (good performance balance)
local MAX_PIRATES_UPDATED_PER_FRAME = 8 -- Performance: limit pirates updated per frame
local MAX_SHIPS_UPDATED_PER_FRAME = 3 -- Performance: limit ships updated per frame

-- Get all active crew codes that have spawned bases
local function getActiveCrewCodes(): { string }
	if not PirateService._getPartyCode then
		return {}
	end
	
	local codes = {}
	for _, player in Players:GetPlayers() do
		local code = PirateService._getPartyCode(player)
		if code and not table.find(codes, code) then
			local baseModel = StarterBaseService.getBaseModel(code)
			if baseModel then
				table.insert(codes, code)
			end
		end
	end
	return codes
end

-- Get the position of a crew's raft
local function getCrewRaftPosition(code: string): Vector3?
	local baseModel = StarterBaseService.getBaseModel(code)
	if not baseModel or not baseModel.PrimaryPart then
		return nil
	end
	return baseModel.PrimaryPart.Position
end

-- Check if it's currently nighttime
local function isNighttime(): boolean
	local state = DayNight.getState(Workspace:GetServerTimeNow())
	-- Only spawn pirates during the Night phase, not during Day or transitions
	return state.phase == "Night" and state.phaseAlpha > 0.1 -- Wait a bit into night before spawning
end

-- Generate a unique ID for ships/pirates
local function generateId(): string
	return tostring(tick()) .. "_" .. tostring(math.random(1000, 9999))
end

-- Find the closest player raft to a position
local function findNearestRaft(position: Vector3): (string?, Vector3?, number?)
	local closestCode = nil
	local closestPos = nil
	local closestDist = math.huge
	
	for _, code in getActiveCrewCodes() do
		local raftPos = getCrewRaftPosition(code)
		if raftPos then
			local distance = (position - raftPos).Magnitude
			if distance < closestDist then
				closestDist = distance
				closestCode = code
				closestPos = raftPos
			end
		end
	end
	
	return closestCode, closestPos, closestDist
end

-- Spawn a new pirate ship near a crew
local function spawnPirateShip(targetCrewCode: string): PirateShip?
	local raftPos = getCrewRaftPosition(targetCrewCode)
	if not raftPos then
		return nil
	end
	
	-- Choose spawn position around the raft (not directly visible)
	local spawnAngle = math.random() * math.pi * 2
	local spawnDistance = SHIP_SPAWN_DISTANCE + math.random(-50, 50)
	local spawnPos = raftPos + Vector3.new(
		math.cos(spawnAngle) * spawnDistance,
		0,
		math.sin(spawnAngle) * spawnDistance
	)
	
	-- Ensure spawn position is over water (adjust Y to sea level)
	spawnPos = Vector3.new(spawnPos.X, Config.StarterBase.Origin.Y, spawnPos.Z)
	
	-- Create ship model
	local shipFolder = Workspace:FindFirstChild("PirateShips")
	if not shipFolder then
		shipFolder = Instance.new("Folder")
		shipFolder.Name = "PirateShips"
		shipFolder.Parent = Workspace
	end
	
	local shipModel = PirateShipFactory.createShip(shipFolder, spawnPos, spawnAngle)
	local shipId = generateId()
	shipModel.Name = "PirateShip_" .. shipId
	
	-- Create pirate ship data
	local ship: PirateShip = {
		model = shipModel,
		id = shipId,
		crew = {},
		targetCrewCode = targetCrewCode,
		lastTargetPos = raftPos,
		spawnTime = Workspace:GetServerTimeNow(),
		state = "hunting",
		health = shipModel:GetAttribute("ShipHealth") or 500,
		maxHealth = shipModel:GetAttribute("ShipHealth") or 500,
	}
	
	-- Spawn pirate crew on the ship
	local crewSize = math.random(2, 4) -- 2-4 pirates per ship
	local shipCenter = shipModel.PrimaryPart.CFrame
	
	for i = 1, crewSize do
		-- Position pirates on deck
		local piratePos = shipCenter * CFrame.new(
			math.random(-8, 8), 
			3,
			math.random(-3, 3)
		)
		
		local weaponType = if math.random() < 0.6 then "cutlass" else "pistol"
		local pirateModel, pirateHumanoid = NpcFactory.createPirate(shipModel, piratePos, {
			shipId = shipId,
			health = 80,
			weapon = weaponType
		})
		
		local pirateId = generateId()
		pirateModel.Name = "Pirate_" .. pirateId
		
		local pirate: PirateNpc = {
			model = pirateModel,
			humanoid = pirateHumanoid,
			shipId = shipId,
			state = "onShip", -- Start on ship and ready to attack
			targetPlayer = nil,
			lastAttackTime = 0,
			homePosition = piratePos.Position,
			weapon = weaponType,
			isHostile = true, -- Pirates are hostile at night by default
			wasAttacked = false, -- Track if pirate was attacked
		}
		
		table.insert(ship.crew, pirate)
		PirateService._npcs[pirateId] = pirate
		
		-- Set up pirate death handling
		pirateHumanoid.Died:Connect(function()
			pirate.state = "dead"
			-- Remove from ship crew
			for j, crewMember in ship.crew do
				if crewMember == pirate then
					table.remove(ship.crew, j)
					break
				end
			end
			PirateService._npcs[pirateId] = nil
		end)
	end
	
	PirateService._ships[shipId] = ship
	
	-- Set up ship collision handling
	local collisionEvent = shipModel:FindFirstChild("ShipCollision")
	if collisionEvent and collisionEvent:IsA("BindableEvent") then
		collisionEvent.Event:Connect(function(hitModel)
			if hitModel:GetAttribute("IsPlayerBase") then
				-- Player raft collision - switch to attacking mode
				ship.state = "attacking"
				print("[PirateService] Ship", shipId, "collided with player raft, switching to attack mode")
			end
		end)
	end
	
	print("[PirateService] Spawned pirate ship", shipId, "with", crewSize, "pirates targeting crew", targetCrewCode)
	return ship
end

-- Update ship AI and movement
local function updateShipAI(ship: PirateShip, dt: number)
	if not ship.model.Parent then
		return false -- Ship destroyed
	end
	
	local hull = ship.model.PrimaryPart
	if not hull then
		return false
	end
	
	-- Check ship health for destruction
	local currentHealth = ship.model:GetAttribute("ShipHealth") or ship.maxHealth
	if currentHealth <= 0 then
		print("[PirateService] Ship", ship.id, "destroyed due to damage")
		return false -- Mark for cleanup
	end
	ship.health = currentHealth
	
	local currentPos = hull.Position
	local targetPos = getCrewRaftPosition(ship.targetCrewCode or "")
	
	if not targetPos then
		-- Target crew disconnected, switch to patrol mode
		ship.state = "patrolling"
		ship.targetCrewCode = nil
		return true
	end
	
	ship.lastTargetPos = targetPos
	local distanceToTarget = (currentPos - targetPos).Magnitude
	
	-- Check if ship should despawn (too far from any players)
	if distanceToTarget > SHIP_DESPAWN_DISTANCE then
		return false -- Mark for cleanup
	end
	
	-- Get ship movement components
	local bodyVelocity = hull:FindFirstChild("BodyVelocity")
	local bodyAngularVelocity = hull:FindFirstChild("BodyAngularVelocity")
	
	if not bodyVelocity or not bodyAngularVelocity then
		return true -- Continue without movement
	end
	
	-- Ship AI behavior based on state
	if ship.state == "hunting" then
		if distanceToTarget < ATTACK_RANGE then
			ship.state = "attacking"
		else
			-- Move toward target
			local direction = (targetPos - currentPos).Unit
			local speed = ship.model:GetAttribute("MaxSpeed") or 60
			bodyVelocity.Velocity = direction * speed
			
			-- Rotate toward target
			local lookDirection = direction
			local currentLook = hull.CFrame.LookVector
			local turnError = math.atan2(currentLook:Cross(lookDirection).Y, currentLook:Dot(lookDirection))
			local turnSpeed = ship.model:GetAttribute("TurnSpeed") or 2
			bodyAngularVelocity.AngularVelocity = Vector3.new(0, turnError * turnSpeed, 0)
		end
		
	elseif ship.state == "attacking" then
		if distanceToTarget > ATTACK_RANGE * 1.5 then
			ship.state = "hunting" -- Resume hunting if target moves away
		else
			-- Circle around target for attack runs
			local angle = (Workspace:GetServerTimeNow() - ship.spawnTime) * 0.5
			local circleRadius = ATTACK_RANGE * 0.8
			local circlePos = targetPos + Vector3.new(
				math.cos(angle) * circleRadius,
				0,
				math.sin(angle) * circleRadius
			)
			
			local direction = (circlePos - currentPos).Unit
			local speed = (ship.model:GetAttribute("MaxSpeed") or 60) * 0.8
			bodyVelocity.Velocity = direction * speed
			
			-- Face toward target while circling
			local lookDirection = (targetPos - currentPos).Unit
			local currentLook = hull.CFrame.LookVector
			local turnError = math.atan2(currentLook:Cross(lookDirection).Y, currentLook:Dot(lookDirection))
			bodyAngularVelocity.AngularVelocity = Vector3.new(0, turnError * 3, 0)
		end
		
	elseif ship.state == "patrolling" then
		-- Slow patrol pattern
		local angle = (Workspace:GetServerTimeNow() - ship.spawnTime) * 0.2
		local patrolRadius = 100
		local basePos = ship.lastTargetPos or currentPos
		local patrolPos = basePos + Vector3.new(
			math.cos(angle) * patrolRadius,
			0,
			math.sin(angle) * patrolRadius
		)
		
		local direction = (patrolPos - currentPos).Unit
		local speed = (ship.model:GetAttribute("MaxSpeed") or 60) * 0.4
		bodyVelocity.Velocity = direction * speed
		
		-- Look for new targets while patrolling
		local nearestCode, nearestPos, nearestDist = findNearestRaft(currentPos)
		if nearestCode and nearestDist and nearestDist < ATTACK_RANGE * 2 then
			ship.targetCrewCode = nearestCode
			ship.state = "hunting"
			print("[PirateService] Ship", ship.id, "found new target crew", nearestCode)
		end
	end
	
	return true
end

-- Update pirate NPC AI and combat (optimized)
local function updatePirateAI(pirate: PirateNpc, dt: number)
	if pirate.state == "dead" or not pirate.model.Parent then
		return false
	end
	
	local humanoid = pirate.humanoid
	local model = pirate.model
	local root = model:FindFirstChild("HumanoidRootPart")
	
	if not humanoid or not root or humanoid.Health <= 0 then
		return false
	end
	
	-- Performance optimization: Only update pirate targeting every few frames
	local now = Workspace:GetServerTimeNow()
	local shouldUpdateTargeting = (now % 0.5) < dt -- Update targeting twice per second
	
	-- Check if this pirate was attacked (makes them hostile)
	if not pirate.wasAttacked and humanoid.Health < humanoid.MaxHealth then
		pirate.wasAttacked = true
		pirate.isHostile = true
		print(`[PirateService] Pirate on ship {pirate.shipId} became hostile after taking damage`)
	end
	
	-- Find nearby players to target (only if targeting update is due AND pirate is hostile OR during night)
	-- During nighttime, pirates are aggressive by default
	if pirate.isHostile and (shouldUpdateTargeting or not pirate.targetPlayer) then
		local nearestPlayer = nil
		local nearestDistance = math.huge
		local maxEngageRange = 45 -- studs - good engagement range for nighttime pirate attacks
		
		-- Performance: Only check players, not all characters in workspace
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
			if playerRoot then
				local distance = (root.Position - playerRoot.Position).Magnitude
				if distance < maxEngageRange and distance < nearestDistance then
					nearestDistance = distance
					nearestPlayer = player
				end
			end
		end
		
		pirate.targetPlayer = nearestPlayer
	end
	
	-- Pirate AI behavior - attack players during nighttime
	if pirate.isHostile and pirate.targetPlayer and pirate.targetPlayer.Character then
		pirate.state = "fighting"
		
		local playerRoot = pirate.targetPlayer.Character:FindFirstChild("HumanoidRootPart")
		if playerRoot then
			local direction = (playerRoot.Position - root.Position).Unit
			local distance = (playerRoot.Position - root.Position).Magnitude
			
			-- Move toward player (aggressive chase AI during night)
			local moveSpeed = 12 -- studs per second - good speed for pirate attacks
			local newPos = root.Position + direction * moveSpeed * dt
			
			-- Performance: Use CFrame.lookAt less frequently for smooth movement
			if (now % 0.2) < dt then -- Update look direction 5 times per second
				root.CFrame = CFrame.lookAt(newPos, playerRoot.Position)
			else
				root.CFrame = root.CFrame + (newPos - root.Position)
			end
			
			-- Attack if in range
			local attackRange = if pirate.weapon == "cutlass" then 8 else 25
			if distance < attackRange then
				local attackCooldown = if pirate.weapon == "cutlass" then 1.2 else 2.0 -- Normal attack speeds
				
				if now - pirate.lastAttackTime >= attackCooldown then
					pirate.lastAttackTime = now
					
					local playerHumanoid = pirate.targetPlayer.Character:FindFirstChildOfClass("Humanoid")
					if playerHumanoid then
						if pirate.weapon == "cutlass" then
							playerHumanoid:TakeDamage(15) -- Normal pirate melee damage
						elseif pirate.weapon == "pistol" then
							playerHumanoid:TakeDamage(20) -- Normal pirate ranged damage
						end
					end
				end
			end
		end
	else
		-- No target or not hostile, return to ship position
		pirate.targetPlayer = nil
		pirate.state = "onShip"
		
		local homeDirection = (pirate.homePosition - root.Position).Unit
		local returnSpeed = 8 -- Normal return speed
		local newPos = root.Position + homeDirection * returnSpeed * dt
		
		-- Performance: Smooth return movement without excessive CFrame.lookAt calls
		if (now % 0.3) < dt then -- Update look direction ~3 times per second
			root.CFrame = CFrame.lookAt(newPos, pirate.homePosition)
		else
			root.CFrame = root.CFrame + (newPos - root.Position)
		end
	end
	
	return true
end

-- Main update loop for all pirates and ships (with performance optimization)
local function updatePirateSystem(dt: number)
	PirateService._updateAccumulator += dt
	if PirateService._updateAccumulator < UPDATE_FREQUENCY then
		return
	end
	local deltaTime = PirateService._updateAccumulator
	PirateService._updateAccumulator = 0
	
	-- Early exit if it's daytime (no pirates should be active)
	if not isNighttime() then
		-- Despawn any lingering pirates from previous night
		if next(PirateService._ships) then
			despawnAllPirates()
		end
		return
	end
	
	-- Performance optimization: Update ships in batches to prevent frame drops
	local shipIds = {}
	for shipId in PirateService._ships do
		table.insert(shipIds, shipId)
	end
	
	local shipsToRemove = {}
	local shipsUpdated = 0
	
	for _, shipId in shipIds do
		if shipsUpdated >= MAX_SHIPS_UPDATED_PER_FRAME then
			break -- Defer remaining ships to next frame
		end
		
		local ship = PirateService._ships[shipId]
		if ship then
			local shouldKeep = updateShipAI(ship, deltaTime)
			if not shouldKeep then
				table.insert(shipsToRemove, shipId)
			end
			shipsUpdated += 1
		end
	end
	
	-- Clean up destroyed/despawned ships
	for _, shipId in shipsToRemove do
		local ship = PirateService._ships[shipId]
		if ship then
			print("[PirateService] Despawning ship", shipId)
			-- Clean up crew
			for _, pirate in ship.crew do
				pirate.state = "dead"
			end
			-- Destroy ship model safely
			pcall(function()
				PirateShipFactory.destroyShip(ship.model)
			end)
			PirateService._ships[shipId] = nil
		end
	end
	
	-- Performance optimization: Update pirates in batches
	local pirateIds = {}
	for pirateId in PirateService._npcs do
		table.insert(pirateIds, pirateId)
	end
	
	local piratesToRemove = {}
	local piratesUpdated = 0
	
	for _, pirateId in pirateIds do
		if piratesUpdated >= MAX_PIRATES_UPDATED_PER_FRAME then
			break -- Defer remaining pirates to next frame
		end
		
		local pirate = PirateService._npcs[pirateId]
		if pirate then
			local shouldKeep = updatePirateAI(pirate, deltaTime)
			if not shouldKeep then
				table.insert(piratesToRemove, pirateId)
			end
			piratesUpdated += 1
		end
	end
	
	-- Clean up dead pirates
	for _, pirateId in piratesToRemove do
		PirateService._npcs[pirateId] = nil
	end
end

-- Check if new pirate ships should be spawned
local function checkPirateSpawning()
	local now = Workspace:GetServerTimeNow()
	if now - PirateService._lastSpawnCheck < SPAWN_CHECK_INTERVAL then
		return
	end
	PirateService._lastSpawnCheck = now
	
	-- Only spawn during nighttime
	if not isNighttime() then
		return
	end
	
	-- Check each active crew for pirate spawning
	local activeCrews = getActiveCrewCodes()
	local totalShips = 0
	for _ in PirateService._ships do
		totalShips += 1
	end
	
	if totalShips >= MAX_TOTAL_SHIPS then
		return -- Global ship limit reached
	end
	
	for _, crewCode in activeCrews do
		-- Count ships targeting this crew
		local shipsTargetingCrew = 0
		for _, ship in PirateService._ships do
			if ship.targetCrewCode == crewCode then
				shipsTargetingCrew += 1
			end
		end
		
		-- Spawn new ship if under limit and RNG succeeds
		if shipsTargetingCrew < MAX_SHIPS_PER_CREW then
			if math.random() < PIRATE_SPAWN_CHANCE then
				local newShip = spawnPirateShip(crewCode)
				if newShip then
					totalShips += 1
					if totalShips >= MAX_TOTAL_SHIPS then
						break -- Stop spawning if global limit reached
					end
				end
			end
		end
	end
end

-- Despawn all pirates at dawn
local function despawnAllPirates()
	print("[PirateService] Dawn arrived - despawning all pirates")
	
	-- Mark all ships for removal
	local allShipIds = {}
	for shipId in PirateService._ships do
		table.insert(allShipIds, shipId)
	end
	
	for _, shipId in allShipIds do
		local ship = PirateService._ships[shipId]
		if ship then
			-- Clean up crew
			for _, pirate in ship.crew do
				pirate.state = "dead"
				if pirate.model.Parent then
					pirate.model:Destroy()
				end
			end
			-- Destroy ship model
			PirateShipFactory.destroyShip(ship.model)
			PirateService._ships[shipId] = nil
		end
	end
	
	-- Clear all NPCs
	PirateService._npcs = {}
	
	print("[PirateService] All pirates despawned for dawn")
end

-- Monitor day/night transitions
local function monitorDayNight()
	local lastPhase = nil
	
	RunService.Heartbeat:Connect(function()
		local state = DayNight.getState(Workspace:GetServerTimeNow())
		if lastPhase and lastPhase ~= state.phase then
			if state.phase == "Day" then
				despawnAllPirates()
			elseif state.phase == "Night" then
				print("[PirateService] Night has fallen - pirates may spawn")
			end
		end
		lastPhase = state.phase
	end)
end

-- Public API
function PirateService.start(
	toastRemote: RemoteEvent,
	getPartyCodeFn: (Player) -> string?,
	getMemberUserIdsFn: (string) -> { number }
)
	if PirateService._started then
		return
	end
	PirateService._started = true
	
	PirateService._Toast = toastRemote
	PirateService._getPartyCode = getPartyCodeFn
	PirateService._getMemberUserIds = getMemberUserIdsFn
	
	print("[PirateService] Starting pirate system...")
	
	-- Set up update loops
	RunService.Heartbeat:Connect(updatePirateSystem)
	
	-- Set up spawning checks
	task.spawn(function()
		while PirateService._started do
			checkPirateSpawning()
			task.wait(SPAWN_CHECK_INTERVAL)
		end
	end)
	
	-- Monitor day/night cycle
	monitorDayNight()
	
	print("[PirateService] Pirate system started - ships will spawn at night")
end

function PirateService.getActiveShips(): { [string]: PirateShip }
	return PirateService._ships
end

function PirateService.getActivePirates(): { [string]: PirateNpc }
	return PirateService._npcs
end

-- Force spawn a pirate ship for testing (ignores night requirement)
function PirateService.forceSpawnShip(targetCrewCode: string): PirateShip?
	return spawnPirateShip(targetCrewCode)
end

-- Emergency cleanup (for server shutdown or debugging)
function PirateService.cleanup()
	despawnAllPirates()
	PirateService._started = false
	print("[PirateService] Emergency cleanup completed")
end

return PirateService