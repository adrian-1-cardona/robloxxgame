-- RemoteEvent / RemoteFunction folder contract.
-- Server creates the folder; client waits for it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local FOLDER_NAME = "SurviveAtSeaRemotes"

function Remotes.getFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 30)
	assert(folder and folder:IsA("Folder"), "Survive at Sea remotes folder missing")
	return folder
end

function Remotes.waitFor(name: string): Instance
	local folder = Remotes.getFolder()
	local remote = folder:WaitForChild(name, 30)
	assert(remote, `Remote '{name}' missing`)
	return remote
end

function Remotes.createServerRemotes(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not (folder and folder:IsA("Folder")) then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	local names = {
		"CreateParty",
		"JoinParty",
		"LeaveParty",
		"PartyUpdated",
		"PortalsUpdated",
		"Toast",
		"GetLobbyState",
		-- Helm: client sends camera look + throttle while steering; server pushes mount state
		"HelmLook",
		"HelmThrottle",
		"HelmState",
		"HelmDismount",
		-- Melee: client requests a swing; server validates + damages; SwingFx for other clients
		"MeleeAttack",
		"MeleeSwingFx",
	}

	for _, name in names do
		if folder:FindFirstChild(name) then
			continue
		end
		local remote: Instance
		if name == "GetLobbyState" then
			remote = Instance.new("RemoteFunction")
		else
			remote = Instance.new("RemoteEvent")
		end
		remote.Name = name
		remote.Parent = folder
	end

	return folder
end

return Remotes
