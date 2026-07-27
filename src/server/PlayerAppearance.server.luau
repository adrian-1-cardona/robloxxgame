-- Keep every sailor at the standard Roblox R15 body scale.  Account avatar
-- settings can otherwise make a player much shorter or taller than the island
-- villagers, and can put their camera inside the helm wheel.

local Players = game:GetService("Players")

local STANDARD_SCALES = {
	BodyDepthScale = 1,
	BodyHeightScale = 1,
	BodyWidthScale = 1,
	HeadScale = 1,
	BodyTypeScale = 0,
	ProportionScale = 0,
}

local function setStandardCharacterScale(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end

	-- R6 avatars do not expose scale values and are already the normal Roblox
	-- height. R15 values may arrive just after the Humanoid, so wait briefly for
	-- each one rather than assuming the character's initial descendants are final.
	for name, value in STANDARD_SCALES do
		local scale = humanoid:FindFirstChild(name) or humanoid:WaitForChild(name, 3)
		if scale and scale:IsA("NumberValue") then
			scale.Value = value
		end
	end
end

local function connectPlayer(player: Player)
	player.CharacterAdded:Connect(setStandardCharacterScale)
	if player.Character then
		task.spawn(setStandardCharacterScale, player.Character)
	end
end

Players.PlayerAdded:Connect(connectPlayer)
for _, player in Players:GetPlayers() do
	connectPlayer(player)
end
