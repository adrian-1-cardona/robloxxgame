--!nocheck
-- ============================================================================
-- Survive at Sea · Portal "load into a game" regression test
-- ============================================================================
--
-- WHAT THIS GUARDS
-- ----------------
-- This is the canonical "the portals work" test. It reproduces, headlessly,
-- the exact path a player takes to LOAD INTO A GAME:
--
--     1. Walk a pier portal            -> PartyService.createParty(...)
--     2. Get seated onto your raft      -> StarterBaseService.ensureBase + teleport
--     3. Friends join by code           -> PartyService.joinParty(...)
--
-- If any assertion here fails, a player can NO LONGER reliably load into a
-- game from the portals -- so the PR/commit MUST NOT be merged until it is
-- green again. This preserves the known-good state as of the commit that
-- introduced this test.
--
-- HOW IT RUNS WITHOUT ROBLOX STUDIO
-- ---------------------------------
-- The real server logic (`src/server/PartyService.luau`) is written against
-- the Roblox API. We run it under the standalone Luau runtime "Lune" by:
--   * providing a tiny Roblox environment shim (game / services / datatypes),
--   * loading the REAL PartyService + Config + PartyCode source from disk, and
--   * injecting lightweight stubs for the pure raft-construction services
--     (StarterBaseService / StarterGearService / HelmService) so we can assert
--     the player was actually seated ("loaded in") without building geometry.
--
-- Run locally:   lune run tests/PortalLoad.spec.luau      (from the repo root)
-- ============================================================================

local fs = require("@lune/fs")
local process = require("@lune/process")

-- Base env holds the real Luau stdlib (math/string/table/os/...) that loaded
-- modules inherit through the metatable chain below.
local BASE = getfenv()

-- ----------------------------------------------------------------------------
-- Locate the repository root (works whether run from repo root or /tests).
-- ----------------------------------------------------------------------------
local function fileExists(path: string): boolean
	local ok, isFile = pcall(fs.isFile, path)
	return ok and isFile
end

local ROOT = ""
if fileExists("src/server/PartyService.luau") then
	ROOT = ""
elseif fileExists("../src/server/PartyService.luau") then
	ROOT = "../"
else
	error("[PortalLoad] Could not locate src/server/PartyService.luau — run from the repo root.")
end

-- ----------------------------------------------------------------------------
-- Minimal Roblox datatype shims (only what the loaded modules touch).
-- ----------------------------------------------------------------------------
local Vector3 = {}
Vector3.__index = Vector3
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3)
end
Vector3.zero = Vector3.new(0, 0, 0)

local Color3 = {}
Color3.__index = Color3
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3)
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

local CFrame = {}
CFrame.__index = CFrame
function CFrame.new(...)
	return setmetatable({ args = { ... } }, CFrame)
end

local UDim = {}
function UDim.new(scale, offset)
	return { Scale = scale or 0, Offset = offset or 0 }
end

local UDim2 = {}
function UDim2.new(...)
	return { args = { ... } }
end
function UDim2.fromScale(x, y)
	return { Scale = { x, y } }
end
function UDim2.fromOffset(x, y)
	return { Offset = { x, y } }
end

-- Enum: auto-vivifies categories and items so any Enum.X.Y is a stable token.
local Enum = setmetatable({}, {
	__index = function(self, category)
		local cat = setmetatable({}, {
			__index = function(_, item)
				return { EnumType = category, Name = item }
			end,
		})
		rawset(self, category, cat)
		return cat
	end,
})

local function typeofShim(value)
	local mt = getmetatable(value)
	if mt == Vector3 then
		return "Vector3"
	elseif mt == Color3 then
		return "Color3"
	elseif mt == CFrame then
		return "CFrame"
	end
	return type(value)
end

-- Non-blocking task shim. Nothing in the load-into-game path relies on timing,
-- so deferred/delayed work runs inline (or is dropped for delays).
local task = {
	spawn = function(fn, ...)
		fn(...)
	end,
	defer = function(fn, ...)
		fn(...)
	end,
	delay = function(_seconds, fn, ...)
		-- Debounce/cleanup timers are irrelevant to the synchronous assertions.
		return nil
	end,
	wait = function()
		return 0
	end,
}

-- ----------------------------------------------------------------------------
-- Minimal Roblox instance model.
-- ----------------------------------------------------------------------------
local Instance = {}

local function newInstance(className: string, name: string?)
	local inst = {}
	inst.ClassName = className
	inst.Name = name or className
	inst.Parent = nil
	inst._children = {}

	function inst:GetChildren()
		local out = {}
		for _, c in self._children do
			table.insert(out, c)
		end
		return out
	end

	function inst:FindFirstChild(childName)
		for _, c in self._children do
			if c.Name == childName then
				return c
			end
		end
		return nil
	end

	function inst:WaitForChild(childName, _timeout)
		local found = self:FindFirstChild(childName)
		if not found then
			error(`[PortalLoad shim] {self.Name}:WaitForChild("{childName}") — child not present in test tree`)
		end
		return found
	end

	function inst:IsA(query)
		return self.ClassName == query
	end

	function inst:Destroy()
		if self.Parent then
			local siblings = self.Parent._children
			for i, c in siblings do
				if c == self then
					table.remove(siblings, i)
					break
				end
			end
		end
		self.Parent = nil
	end

	return inst
end

local function addChild(parent, child)
	child.Parent = parent
	table.insert(parent._children, child)
	return child
end

-- ----------------------------------------------------------------------------
-- Fake Players service + player objects.
-- ----------------------------------------------------------------------------
local fakePlayersById: { [number]: any } = {}
local fakePlayerOrder: { any } = {}

local function resetPlayers()
	table.clear(fakePlayersById)
	table.clear(fakePlayerOrder)
end

local function newPlayer(userId: number, displayName: string?)
	local player = {
		UserId = userId,
		Name = displayName or ("User" .. userId),
		DisplayName = displayName or ("User" .. userId),
		Character = nil,
		RespawnLocation = nil,
	}
	fakePlayersById[userId] = player
	table.insert(fakePlayerOrder, player)
	return player
end

local Players = {
	ClassName = "Players",
	Name = "Players",
}
function Players:GetPlayerByUserId(userId)
	return fakePlayersById[userId]
end
function Players:GetPlayers()
	local out = {}
	for _, p in fakePlayerOrder do
		table.insert(out, p)
	end
	return out
end

-- ----------------------------------------------------------------------------
-- Fake Workspace / HttpService.
-- ----------------------------------------------------------------------------
local serverClock = 1000
local Workspace = {
	ClassName = "Workspace",
	Name = "Workspace",
	_children = {},
}
function Workspace:GetServerTimeNow()
	serverClock += 1
	return serverClock
end
function Workspace:FindFirstChild(name)
	for _, c in self._children do
		if c.Name == name then
			return c
		end
	end
	return nil
end

local HttpService = {
	ClassName = "HttpService",
	Name = "HttpService",
}
function HttpService:GenerateGUID(_wrapInCurly)
	local chars = "ABCDEF0123456789"
	local out = {}
	for _ = 1, 8 do
		local i = math.random(1, #chars)
		table.insert(out, string.sub(chars, i, i))
	end
	return table.concat(out)
end

-- ----------------------------------------------------------------------------
-- Instance tree: ReplicatedStorage.Shared + a server folder for PartyService.
-- ----------------------------------------------------------------------------
local ReplicatedStorage = newInstance("ReplicatedStorage", "ReplicatedStorage")
local Shared = addChild(ReplicatedStorage, newInstance("Folder", "Shared"))

local function makeModuleScript(name: string, sourcePath: string)
	local ms = newInstance("ModuleScript", name)
	ms.__sourcePath = sourcePath
	return ms
end

local function makeStubModule(name: string, value: any)
	local ms = newInstance("ModuleScript", name)
	ms.__stub = value
	return ms
end

addChild(Shared, makeModuleScript("Config", ROOT .. "src/shared/Config.luau"))
addChild(Shared, makeModuleScript("PartyCode", ROOT .. "src/shared/PartyCode.luau"))
addChild(Shared, makeModuleScript("Types", ROOT .. "src/shared/Types.luau"))

-- ----------------------------------------------------------------------------
-- Stub construction services + call recorders (proves the player was seated).
-- ----------------------------------------------------------------------------
local calls
local function resetStubs()
	calls = {
		ensureBase = {},
		teleportToBase = {},
		ensureClub = {},
		clearClub = {},
		teleportToLobby = {},
		destroyBase = {},
		releaseHelm = {},
	}
	calls.failNextEnsureBase = false
end
resetStubs()

local StarterBaseStub = {
	ensureBase = function(code, slot)
		if calls.failNextEnsureBase then
			calls.failNextEnsureBase = false
			error("[test] simulated raft build failure")
		end
		table.insert(calls.ensureBase, { code = code, slot = slot })
		return { __base = code, slot = slot }
	end,
	teleportPlayerToBase = function(player, slot, idx)
		table.insert(calls.teleportToBase, { userId = player.UserId, slot = slot, idx = idx })
	end,
	teleportPlayerToLobby = function(player)
		table.insert(calls.teleportToLobby, player.UserId)
	end,
	destroyBase = function(code)
		table.insert(calls.destroyBase, code)
	end,
	getBaseModel = function(code)
		return nil
	end,
	refreshCodeLabel = function(_code) end,
}

local StarterGearStub = {
	ensureStarterClub = function(player)
		table.insert(calls.ensureClub, player.UserId)
	end,
	clearStarterClub = function(player)
		table.insert(calls.clearClub, player.UserId)
	end,
}

local HelmStub = {
	releaseIfHelming = function(player)
		table.insert(calls.releaseHelm, player.UserId)
	end,
}

local serverFolder = newInstance("Folder", "SurviveAtSea")
local partyServiceModule = addChild(serverFolder, makeModuleScript("PartyService", ROOT .. "src/server/PartyService.luau"))
addChild(serverFolder, makeStubModule("StarterBaseService", StarterBaseStub))
addChild(serverFolder, makeStubModule("StarterGearService", StarterGearStub))
addChild(serverFolder, makeStubModule("HelmService", HelmStub))

-- ----------------------------------------------------------------------------
-- Fake `game` DataModel.
-- ----------------------------------------------------------------------------
local services = {
	Players = Players,
	Workspace = Workspace,
	ReplicatedStorage = ReplicatedStorage,
	HttpService = HttpService,
	RunService = { Heartbeat = { Connect = function() end } },
}
local game = {
	ClassName = "DataModel",
	Name = "game",
}
function game:GetService(serviceName)
	local svc = services[serviceName]
	if not svc then
		error(`[PortalLoad shim] game:GetService("{serviceName}") not stubbed`)
	end
	return svc
end
game.Workspace = Workspace

-- ----------------------------------------------------------------------------
-- Module loader: run real .luau source under the shim environment.
-- ----------------------------------------------------------------------------
local sharedEnv = setmetatable({
	game = game,
	workspace = Workspace,
	Instance = Instance,
	Enum = Enum,
	task = task,
	Vector3 = Vector3,
	Color3 = Color3,
	CFrame = CFrame,
	UDim = UDim,
	UDim2 = UDim2,
	typeof = typeofShim,
	tick = function()
		return os.clock()
	end,
	wait = function()
		return 0
	end,
	warn = warn,
	print = print,
}, { __index = BASE })

local moduleCache: { [any]: any } = {}

local function robloxRequire(instance)
	if instance == nil then
		error("[PortalLoad shim] require(nil)")
	end
	local cached = moduleCache[instance]
	if cached ~= nil then
		return cached
	end
	if instance.__stub ~= nil then
		moduleCache[instance] = instance.__stub
		return instance.__stub
	end
	local path = instance.__sourcePath
	if not path then
		error(`[PortalLoad shim] require({instance.Name}) — no source path or stub`)
	end
	local source = fs.readFile(path)
	local chunk, compileErr = loadstring(source, "@" .. instance.Name)
	if not chunk then
		error(`[PortalLoad] failed to compile {instance.Name}: {compileErr}`)
	end
	local env = setmetatable({ script = instance, require = robloxRequire }, { __index = sharedEnv })
	setfenv(chunk, env)
	local result = chunk()
	moduleCache[instance] = result
	return result
end

sharedEnv.require = robloxRequire

-- Re-require PartyService fresh so each test starts from clean singleton state.
local function freshPartyService()
	moduleCache[partyServiceModule] = nil
	resetStubs()
	resetPlayers()
	return robloxRequire(partyServiceModule)
end

-- ----------------------------------------------------------------------------
-- Tiny test framework.
-- ----------------------------------------------------------------------------
local passed = 0
local failed = 0
local failures: { string } = {}

local function fail(message: string)
	error({ __assert = true, message = message }, 0)
end

local function assertTrue(cond: boolean, message: string)
	if not cond then
		fail(message)
	end
end

local function assertEquals(actual, expected, message: string)
	if actual ~= expected then
		fail(`{message} (expected {tostring(expected)}, got {tostring(actual)})`)
	end
end

local function it(name: string, body: () -> ())
	local ok, err = pcall(body)
	if ok then
		passed += 1
		print(`  \27[32mPASS\27[0m  {name}`)
	else
		failed += 1
		local message = if type(err) == "table" and err.__assert then err.message else tostring(err)
		table.insert(failures, `{name}: {message}`)
		print(`  \27[31mFAIL\27[0m  {name}\n          {message}`)
	end
end

-- ----------------------------------------------------------------------------
-- The tests.
-- ----------------------------------------------------------------------------
print("\nSurvive at Sea · Portal load-into-game regression suite\n")

-- Sanity: the shared config that the portal flow depends on loads cleanly.
local Config = robloxRequire(Shared:WaitForChild("Config"))

it("lobby exposes at least one boarding portal", function()
	assertTrue(type(Config.PortalCount) == "number", "Config.PortalCount must be a number")
	assertTrue(Config.PortalCount >= 1, "there must be at least one pier portal")
end)

it("every pier portal reports Ready before anyone boards", function()
	local svc = freshPartyService()
	local infos = svc.getPortalInfos()
	assertEquals(#infos, Config.PortalCount, "portal count mismatch")
	for _, info in infos do
		assertEquals(info.status, "Ready", `portal {info.portalIndex} not Ready`)
	end
end)

it("walking a portal loads the host onto their raft (create crew)", function()
	local svc = freshPartyService()
	local host = newPlayer(101, "Skipper")

	local ok, message, snapshot = svc.createParty(host, 1, 4)
	assertTrue(ok, `createParty failed: {message}`)
	assertTrue(snapshot ~= nil, "createParty returned no snapshot")
	assertTrue(type(snapshot.code) == "string" and #snapshot.code >= 4, "crew code missing/short")
	assertEquals(snapshot.hostUserId, host.UserId, "host mismatch")
	assertEquals(#snapshot.members, 1, "new crew should have exactly the host")

	-- "Loaded into the game" = a raft was ensured AND the host was teleported onto it.
	assertTrue(#calls.ensureBase >= 1, "no raft base was built for the crew")
	assertEquals(#calls.teleportToBase, 1, "host was not seated onto the raft")
	assertEquals(calls.teleportToBase[1].userId, host.UserId, "wrong player seated")
end)

it("the host's lobby state reflects the crew they loaded into", function()
	local svc = freshPartyService()
	local host = newPlayer(102, "Bosun")
	local ok = svc.createParty(host, 1, 4)
	assertTrue(ok, "createParty failed")

	local state = svc.getLobbyState(host)
	assertTrue(state.party ~= nil, "host has no party in lobby state")
	assertEquals(state.party.hostUserId, host.UserId, "lobby state host mismatch")
	assertEquals(#state.portals, Config.PortalCount, "lobby state portals mismatch")
end)

it("all pier portals are usable boarding gates", function()
	for portalIndex = 1, Config.PortalCount do
		local svc = freshPartyService()
		local player = newPlayer(200 + portalIndex, "Deckhand" .. portalIndex)
		local ok, message = svc.createParty(player, portalIndex, 4)
		assertTrue(ok, `portal {portalIndex} could not create a crew: {message}`)
	end
end)

it("non-existent portals are rejected", function()
	local svc = freshPartyService()
	local player = newPlayer(300, "Stray")

	local okLow = svc.createParty(player, 0, 4)
	assertTrue(not okLow, "portal index 0 should be rejected")

	local player2 = newPlayer(301, "Stray2")
	local okHigh = svc.createParty(player2, Config.PortalCount + 1, 4)
	assertTrue(not okHigh, "out-of-range portal index should be rejected")
end)

it("a friend can load in by crew code", function()
	local svc = freshPartyService()
	local host = newPlayer(400, "Captain")
	local friend = newPlayer(401, "Mate")

	local ok, _, snapshot = svc.createParty(host, 1, 4)
	assertTrue(ok and snapshot ~= nil, "host could not create a crew")

	local joinOk, joinMsg, joinSnap = svc.joinParty(friend, snapshot.code)
	assertTrue(joinOk, `friend could not join by code: {joinMsg}`)
	assertEquals(#joinSnap.members, 2, "crew should now have 2 members")

	-- The friend must actually be seated onto the same raft (loaded in).
	local friendSeated = false
	for _, seat in calls.teleportToBase do
		if seat.userId == friend.UserId then
			friendSeated = true
		end
	end
	assertTrue(friendSeated, "friend was not seated onto the raft")
end)

it("a wrong code does not load anyone in", function()
	local svc = freshPartyService()
	local host = newPlayer(500, "Host")
	local stranger = newPlayer(501, "Stranger")
	svc.createParty(host, 1, 4)

	local ok, message = svc.joinParty(stranger, "ZZZZ")
	assertTrue(not ok, "joining a non-existent code should fail")
	assertTrue(not svc.isInParty(stranger), "stranger must not be on a crew")
	assertTrue(type(message) == "string" and #message > 0, "failure needs a user message")
end)

it("a full crew rejects extra joiners", function()
	local svc = freshPartyService()
	local host = newPlayer(600, "One")
	local ok, _, snapshot = svc.createParty(host, 1, 2) -- maxPlayers = 2
	assertTrue(ok, "createParty failed")

	local two = newPlayer(601, "Two")
	assertTrue((svc.joinParty(two, snapshot.code)), "second member should fit")

	local three = newPlayer(602, "Three")
	local okThree, msgThree = svc.joinParty(three, snapshot.code)
	assertTrue(not okThree, "third joiner should be rejected on a full crew")
	assertTrue(string.find(string.lower(msgThree), "full") ~= nil, "full-crew message expected")
end)

it("you cannot create a second crew while already on one", function()
	local svc = freshPartyService()
	local host = newPlayer(700, "Busy")
	assertTrue((svc.createParty(host, 1, 4)), "first createParty failed")
	local ok = svc.createParty(host, 2, 4)
	assertTrue(not ok, "creating a second crew while in one should fail")
end)

it("portals stay reusable & Ready after a crew empties out", function()
	local svc = freshPartyService()
	local host = newPlayer(800, "Solo")
	local ok, _, snapshot = svc.createParty(host, 1, 4)
	assertTrue(ok, "createParty failed")

	local leftOk = svc.leaveParty(host)
	assertTrue(leftOk, "leaveParty should succeed")
	assertTrue(not svc.isInParty(host), "player should be off the crew after leaving")
	assertTrue(#calls.destroyBase >= 1, "empty crew's raft should be torn down")

	-- Regression guard: after a crew empties, every portal must still be Ready
	-- so the next player can board (portals are reusable boarding gates).
	local infos = svc.getPortalInfos()
	assertEquals(#infos, Config.PortalCount, "portal count changed after crew emptied")
	for _, info in infos do
		assertEquals(info.status, "Ready", `portal {info.portalIndex} not Ready after crew emptied`)
	end

	-- And a brand-new player can immediately board again.
	local next = newPlayer(801, "NextUp")
	assertTrue((svc.createParty(next, 1, 4)), "portal should be reusable for the next crew")
end)

it("a failed raft build does not strand the player on a dead crew", function()
	local svc = freshPartyService()
	local player = newPlayer(900, "Unlucky")

	calls.failNextEnsureBase = true
	local ok = svc.createParty(player, 1, 4)
	assertTrue(not ok, "createParty should fail when the raft can't be built")

	-- The critical regression: the player must be fully rolled back, NOT stuck
	-- "in a crew" with no raft (which historically left portals feeling dead).
	assertTrue(not svc.isInParty(player), "player must be rolled back after a build failure")

	-- They can immediately try again and succeed.
	local retryOk = svc.createParty(player, 1, 4)
	assertTrue(retryOk, "player should be able to board again after a failed attempt")
end)

-- ----------------------------------------------------------------------------
-- Summary / exit code.
-- ----------------------------------------------------------------------------
print(`\nResults: {passed} passed, {failed} failed\n`)

if failed > 0 then
	print("\27[31mPortal load-into-game test FAILED — do not merge until this is green.\27[0m")
	for _, line in failures do
		print("  - " .. line)
	end
	process.exit(1)
end

print("\27[32mAll portal load-into-game checks passed — players can board a game.\27[0m")
process.exit(0)
