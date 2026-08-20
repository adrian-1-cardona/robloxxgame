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
PirateService._getCycleOrigin = nil :: ((string) -> number?)?
PirateService._started = false

-- Configuration
local MAX_SHIPS_PER_CREW = 1 -- One focused encounter per crew keeps the sea readable.
local MAX_TOTAL_SHIPS = 4 -- Hard cap protects the server when several crews sail together.
local SPAWN_CHECK_INTERVAL = 6 -- seconds (balanced spawn timing)
local SHIP_SPAWN_DISTANCE = 200 -- studs from player raft
local SHIP_DESPAWN_DISTANCE = 400 -- studs - ships despawn if too far
local ATTACK_RANGE = 150 -- studs - ships start attacking in this range
local PIRATE_SPAWN_CHANCE = 0.65 -- 65% chance per spawn check during night - active but not overwhelming
local UPDATE_FREQUENCY = 0.15 -- seconds between AI updates (good performance balance)
local MAX_PIRATES_UPDATED_PER_FRAME = 12 -- Four ships × three crew members at the cap.
local MAX_SHIPS_UPDATED_PER_FRAME = 4 -- Every active ship receives an AI tick; none starve.

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

-- Night is per-crew: each voyage starts at 9:00 AM from its own cycleOrigin.
-- Using absolute server time would desync pirate attacks from the clock the players see.
local function isNightForCrew(code: string): boolean
	local origin = if PirateService._getCycleOrigin then PirateService._getCycleOrigin(code) else nil
	local state = DayNight.getState(Workspace:GetServerTimeNow(), origin)
	return state.phase == "Night" and state.phaseAlpha > 0.05
end

local function anyCrewInNight(): boolean
	for _, code in getActiveCrewCodes() do
		if isNightForCrew(code) then
			return true
		end
	end
	return false
end

local function crewsInNight(): { string }
	local nightCrews = {}
	for _, code in getActiveCrewCodes() do
		if isNightForCrew(code) then
			table.insert(nightCrews, code)
		end
	end
	return nightCrews
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

-- Pirate ship parts are intentionally anchored so they are stable on the client and do not
-- wake a large physics assembly. Move the whole model at the throttled AI rate instead.
-- PivotTo also carries the pirate models on deck, avoiding a separate per-part move.
local function sailShip(ship: PirateShip, direction: Vector3, speed: number, dt: number)
	local hull = ship.model.PrimaryPart
	if not hull or direction.Magnitude < 0.01 then
		return
	end
	local oldPivot = ship.model:GetPivot()
	local flatDirection = Vector3.new(direction.X, 0, direction.Z).Unit
	local desired = CFrame.lookAt(oldPivot.Position, oldPivot.Position + flatDirection)
	local turnAlpha = math.clamp(dt * 2.6, 0, 1)
	local facing = oldPivot:Lerp(desired, turnAlpha).LookVector
	local step = math.min(speed * dt, 12) -- cap catch-up after a slow server frame
	local nextPos = oldPivot.Position + flatDirection * step
	local nextPivot = CFrame.lookAt(nextPos, nextPos + Vector3.new(facing.X, 0, facing.Z).Unit)
	ship.model:PivotTo(nextPivot)

	-- Home positions are world coordinates; carry them with the ship so idle pirates stay on deck.
	local delta = nextPivot * oldPivot:Inverse()
	for _, pirate in ship.crew do
		pirate.homePosition = (delta * CFrame.new(pirate.homePosition)).Position
	end
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
	
	-- Ship AI behavior based on state
	if ship.state == "hunting" then
		if distanceToTarget < ATTACK_RANGE then
			ship.state = "attacking"
		else
			-- Move toward target
			local direction = (targetPos - currentPos).Unit
			local speed = ship.model:GetAttribute("MaxSpeed") or 60
			sailShip(ship, direction, speed, dt)
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
			sailShip(ship, direction, speed, dt)
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
		sailShip(ship, direction, speed, dt)
		
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
	
	-- Despawn ships whose target crew has returned to daytime; keep fighting for night crews.
	if not anyCrewInNight() then
		if next(PirateService._ships) then
			despawnAllPirates()
		end
		return
	end

	-- Drop ships that are still hunting a crew whose voyage day has begun.
	local dawnTargets = {}
	for shipId, ship in PirateService._ships do
		local code = ship.targetCrewCode
		if code and not isNightForCrew(code) then
			table.insert(dawnTargets, shipId)
		end
	end
	for _, shipId in dawnTargets do
		local ship = PirateService._ships[shipId]
		if ship then
			print("[PirateService] Despawning ship", shipId, "- target crew reached dawn")
			for _, pirate in ship.crew do
				pirate.state = "dead"
			end
			pcall(function()
				PirateShipFactory.destroyShip(ship.model)
			end)
			PirateService._ships[shipId] = nil
		end
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
	
	-- Only spawn against crews whose voyage clock is currently night
	local nightCrews = crewsInNight()
	if #nightCrews == 0 then
		return
	end
	
	-- Check each night crew for pirate spawning
	local totalShips = 0
	for _ in PirateService._ships do
		totalShips += 1
	end
	
	if totalShips >= MAX_TOTAL_SHIPS then
		return -- Global ship limit reached
	end
	
	for _, crewCode in nightCrews do
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

-- Monitor day/night transitions per active crew voyage clock
local function monitorDayNight()
	local lastNightByCode: { [string]: boolean } = {}
	
	RunService.Heartbeat:Connect(function()
		local active = getActiveCrewCodes()
		local seen: { [string]: boolean } = {}
		for _, code in active do
			seen[code] = true
			local night = isNightForCrew(code)
			local wasNight = lastNightByCode[code]
			if wasNight == false and night then
				print("[PirateService] Night has fallen for crew", code, "- pirates may spawn")
			elseif wasNight == true and not night then
				print("[PirateService] Dawn arrived for crew", code)
			end
			lastNightByCode[code] = night
		end
		for code in lastNightByCode do
			if not seen[code] then
				lastNightByCode[code] = nil
			end
		end
	end)
end

-- Public API
function PirateService.start(
	toastRemote: RemoteEvent,
	getPartyCodeFn: (Player) -> string?,
	getMemberUserIdsFn: (string) -> { number },
	getCycleOriginFn: ((string) -> number?)?
)
	if PirateService._started then
		return
	end
	PirateService._started = true
	
	PirateService._Toast = toastRemote
	PirateService._getPartyCode = getPartyCodeFn
	PirateService._getMemberUserIds = getMemberUserIdsFn
	PirateService._getCycleOrigin = getCycleOriginFn
	
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
	
	print("[PirateService] Pirate system started - ships attack crews during their voyage nights")
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
