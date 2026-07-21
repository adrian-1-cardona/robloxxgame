-- Server helpers around the shared LobbyWorld boarding pier.
-- Geometry + polish live in Shared.LobbyWorld so client fallback stays in sync.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))

local LobbyBuilder = {}

local function safeLighting()
	local ok, err = pcall(function()
		-- Warm late-afternoon harbor light (no bloom / no neon glare)
		Lighting.ClockTime = 17.1
		Lighting.Brightness = 2.6
		Lighting.Ambient = Color3.fromRGB(78, 92, 98)
		Lighting.OutdoorAmbient = Color3.fromRGB(118, 128, 132)
		Lighting.FogColor = Color3.fromRGB(140, 175, 190)
		Lighting.FogStart = 220
		Lighting.FogEnd = 1100
		Lighting.GlobalShadows = true
		Lighting.EnvironmentDiffuseScale = 0.55
		Lighting.EnvironmentSpecularScale = 0.35

		for _, child in Lighting:GetChildren() do
			if child:IsA("Atmosphere") or child:IsA("BloomEffect") or child:IsA("ColorCorrectionEffect") or child:IsA("SunRaysEffect") then
				child:Destroy()
			end
		end

		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.12
		atmosphere.Offset = 0.18
		atmosphere.Color = Color3.fromRGB(175, 190, 200)
		atmosphere.Decay = Color3.fromRGB(70, 95, 120)
		atmosphere.Glare = 0
		atmosphere.Haze = 0.35
		atmosphere.Parent = Lighting

		local sky = Lighting:FindFirstChildOfClass("Sky")
		if not sky then
			sky = Instance.new("Sky")
			sky.Parent = Lighting
		end
		sky.CelestialBodiesShown = true
		sky.StarCount = 600
		sky.SunAngularSize = 20
		sky.MoonAngularSize = 11

		local cc = Instance.new("ColorCorrectionEffect")
		cc.TintColor = Color3.fromRGB(255, 246, 236)
		cc.Contrast = 0.06
		cc.Saturation = 0.05
		cc.Brightness = 0.02
		cc.Parent = Lighting
	end)
	if not ok then
		warn("[SurviveAtSea] Lighting setup failed (lobby still builds):", err)
	end
end

local function clearWorkspaceClutter()
	for _, name in { "Baseplate", "SpawnLocation", "Terrain" } do
		local inst = Workspace:FindFirstChild(name)
		if inst and not inst:IsA("Terrain") then
			inst:Destroy()
		end
	end

	for _, child in Workspace:GetChildren() do
		if child:IsA("BasePart") or child:IsA("Model") or child:IsA("Folder") then
			if child.Name ~= "SurviveAtSeaLobby" and child.Name ~= "Camera" and child.Name ~= "Terrain" then
				local isCharacter = false
				for _, plr in Players:GetPlayers() do
					if plr.Character == child then
						isCharacter = true
						break
					end
				end
				if not isCharacter then
					child:Destroy()
				end
			end
		end
	end
end

function LobbyBuilder.enhanceExisting(root: Folder)
	safeLighting()
	LobbyWorld.polish(root)
	print("[SurviveAtSea] Enhanced existing lobby map")
end

function LobbyBuilder.build(): Folder
	local existing = Workspace:FindFirstChild("SurviveAtSeaLobby")
	if existing then
		existing:Destroy()
	end

	clearWorkspaceClutter()
	safeLighting()
	local root = LobbyWorld.ensure()
	print("[SurviveAtSea] Lobby geometry built — pier +", Config.PortalCount, "berths")
	return root
end

function LobbyBuilder.updatePortalSign(portalModel: Model, title: string, subtitle: string, color: Color3?)
	LobbyWorld.updatePortalSign(portalModel, title, subtitle, color)
end

function LobbyBuilder.getPortalModel(index: number): Model?
	local root = Workspace:FindFirstChild("SurviveAtSeaLobby")
	if not root then
		return nil
	end
	local portals = root:FindFirstChild("Portals")
	if not portals then
		return nil
	end
	local model = portals:FindFirstChild("Portal_" .. index)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

function LobbyBuilder.getVoyageSpawnCFrame(): CFrame
	return CFrame.new(0, 6, 620)
end

function LobbyBuilder.getLobbySpawnCFrame(): CFrame
	return LobbyWorld.getLobbySpawnCFrame()
end

function LobbyBuilder.teleportPlayerToLobby(player: Player)
	local character = player.Character
	if not character then
		return
	end
	LobbyWorld.seatCharacter(character)
end

return LobbyBuilder
