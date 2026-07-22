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
		-- Ranged weapon fire (pistol / revolver / rifle / shotgun / musket / bow / flintlock).
		-- Client sends aim look vector; server validates ammo + raycasts + damages.
		"ShootGun",
		-- Reload the equipped ranged weapon from carried ammo reserve.
		"WeaponReload",
		-- Fired by the server to broadcast a weapon shot so all clients can play the FX.
		"WeaponFx",
		-- Melee: client requests a swing; server validates + damages; SwingFx for other clients
		"MeleeAttack",
		"MeleeSwingFx",
		-- Loot drag / weld / place (walls, torches, planks, beds, merchant)
		"LootDragStart",
		"LootDragUpdate",
		"LootDragEnd",
		"LootWeld",
		"LootUnweld",
		"LootPlace",
		-- Merchant trading: RemoteFunction the client invokes to buy / craft; server
		-- validates currency and grants the item. MerchantShop pushes the catalog to open UI.
		"MerchantTrade",
		"MerchantShop",
	}

	for _, name in names do
		if folder:FindFirstChild(name) then
			continue
		end
		local remote: Instance
		if name == "GetLobbyState" or name == "MerchantTrade" then
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
