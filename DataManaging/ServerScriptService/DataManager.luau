--!strict
--[[
	DataManager
	───────────
	Session cache + DataStore persistence with schema reconciliation.
	Requires ServerStorage.DataSchema. Lifecycle wiring lives in DataController.server.luau.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local DataSchema = require(ServerStorage:WaitForChild("DataSchema"))

type PlayerData = DataSchema.PlayerData

export type DataPath =
	"Coins"
	| "Level"
	| "Experience"
	| "Inventory"
	| "Stats"
	| "Stats.Kills"
	| "Stats.Deaths"
	| string

local NUMERIC_PATHS: { [string]: true } = {
	Coins = true,
	Level = true,
	Experience = true,
	["Stats.Kills"] = true,
	["Stats.Deaths"] = true,
}

local DATA_STORE_NAME = "PlayerData_v1"
local MAX_RETRIES = 5
local RETRY_BASE_DELAY = 1
local LOAD_FAILURE_KICK_MESSAGE = "Verileriniz şu anda yüklenemedi. Lütfen kısa süre sonra tekrar deneyin."

local DataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)
local SessionData: { [Player]: PlayerData } = {}
local LoadingSessions: { [number]: boolean } = {}

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end

	local copy = {} :: { [any]: any }
	for key, child in value :: { [any]: any } do
		copy[key] = deepCopy(child)
	end

	return copy :: T
end

--[[
	Reconcile(data, template)
	─────────────────────────
	Deep-merges persisted data into the current schema template.
	- Missing keys inherit template defaults.
	- Nested tables recurse (Stats, Inventory, …).
	- Extra keys on leaf dictionaries (e.g. inventory items) are preserved.
	- Type mismatches fall back to the template value.
]]
local function Reconcile(data: any, template: any): any
	if type(template) ~= "table" then
		if data ~= nil and type(data) == type(template) then
			return data
		end
		return template
	end

	local source = if type(data) == "table" then data :: { [any]: any } else {}
	local result: { [any]: any } = {}

	for key, value in source do
		result[key] = if type(value) == "table" then deepCopy(value) else value
	end

	for key, templateValue in template :: { [any]: any } do
		local existing = result[key]

		if type(templateValue) == "table" then
			result[key] = Reconcile(existing, templateValue)
		elseif existing == nil then
			result[key] = if type(templateValue) == "table" then deepCopy(templateValue) else templateValue
		elseif type(existing) ~= type(templateValue) then
			result[key] = templateValue
		end
	end

	return result
end

local function getKey(player: Player): string
	return `user_{player.UserId}`
end

local function splitPath(key: string): { string }
	local parts: { string } = {}
	for segment in string.gmatch(key, "[^%.]+") do
		table.insert(parts, segment)
	end
	return parts
end

local function isInventoryItemPath(key: string): boolean
	local parts = splitPath(key)
	return parts[1] == "Inventory" and #parts == 2
end

local function getAtPath(root: any, key: string): any?
	local parts = splitPath(key)
	if #parts == 0 then
		return nil
	end

	local current: any = root
	for index, segment in parts do
		if type(current) ~= "table" then
			return nil
		end
		current = (current :: { [string]: any })[segment]
		if current == nil and index < #parts then
			return nil
		end
	end

	return current
end

local function isValidDataPath(key: string): boolean
	if key == "" then
		return false
	end
	if isInventoryItemPath(key) then
		return true
	end
	local template = DataSchema.GetDefault()
	return getAtPath(template, key) ~= nil
end

local function setAtPath(root: PlayerData, key: string, value: any): boolean
	if not isValidDataPath(key) then
		warn(`[DataManager] Set rejected: invalid key "{key}"`)
		return false
	end

	local parts = splitPath(key)
	local template = DataSchema.GetDefault()
	local templateValue = getAtPath(template, key)

	if isInventoryItemPath(key) then
		if type(value) ~= "number" then
			warn(`[DataManager] Set rejected: Inventory values must be numbers`)
			return false
		end
	elseif templateValue ~= nil and type(value) ~= type(templateValue) then
		warn(`[DataManager] Set rejected: type mismatch for "{key}"`)
		return false
	end

	local current: any = root
	for index = 1, #parts - 1 do
		local segment = parts[index]
		if type(current) ~= "table" then
			return false
		end
		current = current[segment]
		if current == nil then
			return false
		end
	end

	local leaf = parts[#parts]
	if type(current) ~= "table" then
		return false
	end

	(current :: { [string]: any })[leaf] = value
	return true
end

local function getSession(player: Player): PlayerData?
	local data = SessionData[player]
	if data == nil then
		warn(`[DataManager] No session for {player.Name} ({player.UserId}) — profile not loaded`)
	end
	return data
end

local function withRetry<T>(operation: () -> T): (boolean, T?)
	local lastError: string? = nil

	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end

		lastError = tostring(result)
		if attempt < MAX_RETRIES then
			task.wait(RETRY_BASE_DELAY * attempt)
		end
	end

	warn(`[DataManager] DataStore operation failed after {MAX_RETRIES} attempts: {lastError}`)
	return false, nil
end

local function kickOnLoadFailure(player: Player, reason: string): ()
	warn(`[DataManager] LoadProfile failed for {player.Name} ({player.UserId}): {reason}`)
	if player:IsDescendantOf(Players) then
		player:Kick(LOAD_FAILURE_KICK_MESSAGE)
	end
end

local function saveToStore(player: Player, data: PlayerData): boolean
	local key = getKey(player)

	local template = DataSchema.GetDefault()

	local ok = withRetry(function()
		DataStore:UpdateAsync(key, function()
			local snapshot = Reconcile(data, template) :: PlayerData
			return deepCopy(snapshot)
		end)
		return true
	end)

	return ok == true
end

local DataManager = {}

DataManager.Reconcile = Reconcile

function DataManager.GetData(player: Player): PlayerData?
	return SessionData[player]
end

function DataManager.Get(player: Player, key: string): any?
	if not isValidDataPath(key) then
		warn(`[DataManager] Get rejected: invalid key "{key}"`)
		return nil
	end

	local data = getSession(player)
	if data == nil then
		return nil
	end

	local value = getAtPath(data, key)
	if type(value) == "table" then
		return deepCopy(value)
	end
	return value
end

function DataManager.Set(player: Player, key: string, value: any): boolean
	local data = getSession(player)
	if data == nil then
		return false
	end

	return setAtPath(data, key, value)
end

function DataManager.Increment(player: Player, key: string, amount: number): boolean
	if not NUMERIC_PATHS[key] and not isInventoryItemPath(key) then
		warn(`[DataManager] Increment rejected: "{key}" is not a numeric path`)
		return false
	end

	if type(amount) ~= "number" or amount ~= amount then
		warn(`[DataManager] Increment rejected: amount must be a valid number`)
		return false
	end

	local data = getSession(player)
	if data == nil then
		return false
	end

	local current = getAtPath(data, key)
	if type(current) ~= "number" then
		if isInventoryItemPath(key) then
			current = 0
		else
			warn(`[DataManager] Increment rejected: "{key}" is not numeric`)
			return false
		end
	end

	return setAtPath(data, key, (current :: number) + amount)
end

function DataManager.IsLoaded(player: Player): boolean
	return SessionData[player] ~= nil
end

function DataManager.LoadProfile(player: Player): boolean
	if not player:IsDescendantOf(Players) then
		return false
	end

	local userId = player.UserId
	if SessionData[player] ~= nil then
		return true
	end

	if LoadingSessions[userId] then
		return false
	end

	LoadingSessions[userId] = true

	local key = getKey(player)
	local template = DataSchema.GetDefault()

	local ok, raw = withRetry(function()
		return DataStore:GetAsync(key)
	end)

	LoadingSessions[userId] = nil

	if not ok then
		kickOnLoadFailure(player, "DataStore GetAsync failed")
		return false
	end

	local data = Reconcile(raw, template) :: PlayerData
	SessionData[player] = data
	return true
end

function DataManager.LoadPlayer(player: Player): PlayerData?
	if DataManager.LoadProfile(player) then
		return SessionData[player]
	end
	return nil
end

function DataManager.SaveProfile(player: Player): boolean
	local data = SessionData[player]
	if data == nil then
		return false
	end

	if not saveToStore(player, data) then
		warn(`[DataManager] SaveProfile failed for {player.Name} ({player.UserId})`)
		return false
	end

	SessionData[player] = nil
	return true
end

function DataManager.SavePlayer(player: Player): boolean
	local data = SessionData[player]
	if data == nil then
		return false
	end

	return saveToStore(player, data)
end

function DataManager.ReleasePlayer(player: Player): ()
	if not DataManager.SaveProfile(player) then
		SessionData[player] = nil
	end
	LoadingSessions[player.UserId] = nil
end

function DataManager.SaveAll(): ()
	for player, data in SessionData do
		if player.Parent == Players and data ~= nil then
			saveToStore(player, data)
		end
	end
end

return DataManager
