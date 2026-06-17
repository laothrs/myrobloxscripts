--!strict
--[[
	PlayerDataManager — production-style session cache over SolarchDataStore.

	- Load on join, save on leave (UpdateAsync only)
	- Schema reconciliation after load
	- Deep-copied reads (callers cannot corrupt session cache)
	- BindToClose + periodic auto-save
	- Fail-closed: kick on load failure

	Usage:
		local PlayerDataManager = require(ServerScriptService.SolarchDataStore.PlayerDataManager)
		PlayerDataManager.Init()
		local coins = PlayerDataManager.Get(player, "Coins")
]]

local Players = game:GetService("Players")

local Config = require(script.Parent:WaitForChild("Config"))
local DataSchema = require(script.Parent:WaitForChild("DataSchema"))
local SolarchDataStore = require(script.Parent:WaitForChild("SolarchDataStore"))
local Util = require(script.Parent:WaitForChild("Util"))

export type PlayerData = DataSchema.PlayerData

local PlayerDataManager = {}

local SessionData: { [number]: PlayerData } = {}
local Loaded: { [number]: boolean } = {}
local store = SolarchDataStore:GetDataStore(DataSchema.DataStoreName)

local AUTO_SAVE_INTERVAL = 120
local BIND_TO_CLOSE_TIMEOUT = 30

local function profileKey(userId: number): string
	return "profile_" .. tostring(userId)
end

local function getPathValue(data: any, path: string): any
	local parts = string.split(path, ".")
	local current = data
	for _, part in ipairs(parts) do
		if typeof(current) ~= "table" then
			return nil
		end
		current = current[part]
	end
	return current
end

local function setPathValue(data: any, path: string, value: any): boolean
	local parts = string.split(path, ".")
	local current = data
	for i = 1, #parts - 1 do
		local part = parts[i]
		if typeof(current[part]) ~= "table" then
			current[part] = {}
		end
		current = current[part]
	end
	current[parts[#parts]] = value
	return true
end

function PlayerDataManager.IsLoaded(player: Player): boolean
	return Loaded[player.UserId] == true
end

function PlayerDataManager.Get(player: Player, path: string): any
	local data = SessionData[player.UserId]
	if not data then
		warn(`[PlayerDataManager] Get before load: {player.Name}`)
		return nil
	end
	return Util.deepCopy(getPathValue(data, path))
end

function PlayerDataManager.Set(player: Player, path: string, value: any): boolean
	local data = SessionData[player.UserId]
	if not data then
		return false
	end
	return setPathValue(data, path, value)
end

function PlayerDataManager.Increment(player: Player, path: string, delta: number): boolean
	local current = PlayerDataManager.Get(player, path)
	if typeof(current) ~= "number" then
		current = 0
	end
	return PlayerDataManager.Set(player, path, current + delta)
end

function PlayerDataManager.GetProfile(player: Player): PlayerData?
	local data = SessionData[player.UserId]
	if not data then
		return nil
	end
	return Util.deepCopy(data)
end

function PlayerDataManager.LoadProfile(player: Player): boolean
	local key = profileKey(player.UserId)
	local ok, result = pcall(function()
		return store:GetAsync(key, { UseCache = false })
	end)

	if not ok then
		warn(`[PlayerDataManager] Load failed for {player.Name}: {result}`)
		player:Kick("Could not load your data. Please rejoin.")
		return false
	end

	local profile: PlayerData
	if result == nil then
		profile = Util.deepCopy(DataSchema.DefaultProfile)
	else
		profile = Util.reconcile(result :: any, DataSchema.DefaultProfile) :: PlayerData
	end

	profile.LastLogin = os.time()
	SessionData[player.UserId] = profile
	Loaded[player.UserId] = true
	return true
end

function PlayerDataManager.SaveProfile(player: Player): boolean
	if not Loaded[player.UserId] then
		return false
	end

	local key = profileKey(player.UserId)
	local snapshot = Util.deepCopy(SessionData[player.UserId])

	local ok, err = pcall(function()
		store:UpdateAsync(key, function()
			return snapshot
		end)
	end)

	if not ok then
		warn(`[PlayerDataManager] Save failed for {player.Name}: {err}`)
		return false
	end
	return true
end

function PlayerDataManager.ReleasePlayer(player: Player)
	PlayerDataManager.SaveProfile(player)
	SessionData[player.UserId] = nil
	Loaded[player.UserId] = nil
end

function PlayerDataManager.SaveAll()
	for _, player in Players:GetPlayers() do
		PlayerDataManager.SaveProfile(player)
	end
end

function PlayerDataManager.Init()
	Players.PlayerAdded:Connect(function(player)
		PlayerDataManager.LoadProfile(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlayerDataManager.ReleasePlayer(player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(PlayerDataManager.LoadProfile, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)
			PlayerDataManager.SaveAll()
		end
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(function()
				PlayerDataManager.SaveProfile(player)
			end)
		end
		task.wait(BIND_TO_CLOSE_TIMEOUT)
	end)

	if Config.Debug then
		print("[PlayerDataManager] Initialized")
	end
end

return PlayerDataManager
