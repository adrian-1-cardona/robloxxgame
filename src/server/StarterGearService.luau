-- Grants the starter Club when a player boards a crew raft.
-- Re-grants on respawn if they no longer have one (dropped / lost).
-- Does not grant while on the pier lobby.

local Players = game:GetService("Players")

local ClubToolFactory = require(script.Parent:WaitForChild("Items"):WaitForChild("ClubToolFactory"))

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local StarterGearService = {}

local isInCrew: ((Player) -> boolean)? = nil

local function findClub(container: Instance?): Tool?
	if not container then
		return nil
	end
	for _, child in container:GetChildren() do
		if child:IsA("Tool") and (child.Name == Config.Club.ToolName or child:GetAttribute("ItemId") == "StarterClub") then
			return child
		end
	end
	return nil
end

local function playerHasClub(player: Player): boolean
	if findClub(player:FindFirstChild("Backpack")) then
		return true
	end
	local character = player.Character
	if character and findClub(character) then
		return true
	end
	return false
end

function StarterGearService.ensureStarterClub(player: Player)
	if not isInCrew or not isInCrew(player) then
		return
	end
	if playerHasClub(player) then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		backpack = player:WaitForChild("Backpack", 5)
	end
	if not backpack then
		return
	end

	local club = ClubToolFactory.create()
	club.Parent = backpack
end

function StarterGearService.clearStarterClub(player: Player)
	local backpack = player:FindFirstChild("Backpack")
	local club = findClub(backpack)
	if club then
		club:Destroy()
	end
	local character = player.Character
	if character then
		local held = findClub(character)
		if held then
			held:Destroy()
		end
	end
end

function StarterGearService.start(inCrewCheck: (Player) -> boolean)
	isInCrew = inCrewCheck

	local function onCharacter(player: Player, _character: Model)
		task.defer(function()
			-- Wait a beat so seat/teleport finishes, then grant if still on crew
			task.wait(0.15)
			if player.Parent then
				StarterGearService.ensureStarterClub(player)
			end
		end)
	end

	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end

	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
end

return StarterGearService
