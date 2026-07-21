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
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage

	local names = {
		"CreateParty",
		"JoinParty",
		"LeaveParty",
		"StartLaunch",
		"PartyUpdated",
		"PortalsUpdated",
		"Toast",
		"GetLobbyState",
	}

	for _, name in names do
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
