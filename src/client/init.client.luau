-- Survive at Sea · Client bootstrap

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local LobbyUI = require(script.Lobby.LobbyUI)

print(`[SurviveAtSea] Client hello — welcome aboard {Config.GameName}`)
LobbyUI.start()
