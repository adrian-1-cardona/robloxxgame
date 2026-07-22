-- Survive at Sea · Client bootstrap
-- If Rojo didn't sync the Workspace map (common on existing places like "dnd"),
-- this client builds the boarding dock locally so you still see it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LobbyWorld = require(Shared:WaitForChild("LobbyWorld"))

local LobbyUI = require(script:WaitForChild("Lobby"):WaitForChild("LobbyUI"))
local HelmController = require(script:WaitForChild("Lobby"):WaitForChild("HelmController"))
local OceanController = require(script:WaitForChild("Lobby"):WaitForChild("OceanController"))
local ClockHUD = require(script:WaitForChild("Lobby"):WaitForChild("ClockHUD"))
local WeatherController = require(script:WaitForChild("Gameplay"):WaitForChild("WeatherController"))
local GunController = require(script:WaitForChild("Gameplay"):WaitForChild("GunController"))
local MeleeController = require(script:WaitForChild("Gameplay"):WaitForChild("MeleeController"))
local DragController = require(script:WaitForChild("Gameplay"):WaitForChild("DragController"))
local InventoryHUD = require(script:WaitForChild("Gameplay"):WaitForChild("InventoryHUD"))
local MerchantController = require(script:WaitForChild("Gameplay"):WaitForChild("MerchantController"))

print(`[SurviveAtSea] Client hello — welcome aboard {Config.GameName}`)

-- Prefer a server-replicated lobby; otherwise build one here.
local lobby = Workspace:FindFirstChild("SurviveAtSeaLobby")
if not lobby then
	lobby = Workspace:WaitForChild("SurviveAtSeaLobby", 2)
end
if not lobby then
	print("[SurviveAtSea] No lobby in Workspace yet — building on client")
	lobby = LobbyWorld.ensure()
else
	print("[SurviveAtSea] Found Workspace.SurviveAtSeaLobby")
end

-- Fault isolation: a crash in any single controller must never stop the rest
-- (especially the portal wiring below) from starting.
local function safeStart(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(`[SurviveAtSea] {label} failed to start (lobby still playable):`, err)
	end
end

-- Lighting lock first so lobby stays daytime before any crew UI opens.
safeStart("ClockHUD", ClockHUD.start)
safeStart("LobbyUI", LobbyUI.start)
safeStart("HelmController", HelmController.start)
safeStart("GunController", GunController.start)
safeStart("MeleeController", MeleeController.start)
safeStart("DragController", DragController.start)
safeStart("InventoryHUD", InventoryHUD.start)
safeStart("MerchantController", MerchantController.start)

local player = Players.LocalPlayer

local function seat(character: Model)
	task.defer(function()
		LobbyWorld.seatCharacter(character)
	end)
end

if player.Character then
	seat(player.Character)
end
player.CharacterAdded:Connect(seat)

-- Client-side portal fallback: press E opens create when the server prompt path
-- is unavailable (client-built lobby) or after Rojo replaces portal models.
task.spawn(function()
	local openEvent = ReplicatedStorage:FindFirstChild("SurviveAtSeaOpenCreate")
	if not (openEvent and openEvent:IsA("BindableEvent")) then
		openEvent = Instance.new("BindableEvent")
		openEvent.Name = "SurviveAtSeaOpenCreate"
		openEvent.Parent = ReplicatedStorage
	end

	local wiredPrompts: { [ProximityPrompt]: boolean } = {}
	local folderConn: RBXScriptConnection? = nil
	local lobbyChildConn: RBXScriptConnection? = nil

	local function wirePrompt(model: Model)
		local indexValue = model:FindFirstChild("PortalIndex")
		local promptAnchor = model:FindFirstChild("PromptAnchor")
		local prompt = promptAnchor and promptAnchor:FindFirstChild("BoardPrompt")
		if not (indexValue and indexValue:IsA("IntValue") and prompt and prompt:IsA("ProximityPrompt")) then
			return
		end
		if wiredPrompts[prompt] then
			return
		end
		wiredPrompts[prompt] = true

		local portalIndex = indexValue.Value
		-- Press-E fallback; walk-in is handled by the server PortalService.
		prompt.Triggered:Connect(function()
			(openEvent :: BindableEvent):Fire(portalIndex)
		end)
	end

	local function wirePortalsFolder(portals: Instance)
		if folderConn then
			folderConn:Disconnect()
			folderConn = nil
		end

		for prompt, _ in wiredPrompts do
			if not prompt.Parent then
				wiredPrompts[prompt] = nil
			end
		end

		for _, model in portals:GetChildren() do
			if model:IsA("Model") then
				wirePrompt(model)
			end
		end

		folderConn = portals.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				task.defer(function()
					wirePrompt(child)
				end)
			end
		end)

		print("[SurviveAtSea] Portals wired:", #portals:GetChildren())
	end

	local function bindLobbyInstance(lobbyInstance: Instance)
		if lobbyChildConn then
			lobbyChildConn:Disconnect()
			lobbyChildConn = nil
		end

		local portals = lobbyInstance:FindFirstChild("Portals")
		if portals then
			wirePortalsFolder(portals)
		else
			portals = lobbyInstance:WaitForChild("Portals", 5)
			if portals then
				wirePortalsFolder(portals)
			else
				warn("[SurviveAtSea] Portals folder missing")
			end
		end

		lobbyChildConn = lobbyInstance.ChildAdded:Connect(function(child)
			if child.Name == "Portals" then
				wirePortalsFolder(child)
			end
		end)
	end

	bindLobbyInstance(lobby)

	-- Rojo / server polish can replace the lobby folder after we first bind.
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "SurviveAtSeaLobby" then
			lobby = child
			task.defer(function()
				bindLobbyInstance(child)
			end)
		end
	end)
end)

pcall(function()
	local Lighting = game:GetService("Lighting")
	-- Client ClockHUD owns ClockTime / brightness / fog — only strip neon bloom here.
	for _, child in Lighting:GetChildren() do
		if child:IsA("BloomEffect") then
			child:Destroy()
		end
	end
end)

-- After lighting baseline so underwater fog restore matches the open-sea look.
safeStart("OceanController", OceanController.start)

-- Open-sea weather only (rain / thunder / overcast). Lobby pier stays clear.
safeStart("WeatherController", WeatherController.start)
