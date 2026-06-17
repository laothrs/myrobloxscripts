--!strict
--[[
	Solarch External DataStoreService
	Drop-in replacement for game:GetService("DataStoreService")
]]

local Config = require(script.Parent:WaitForChild("Config"))
local Errors = require(script.Parent:WaitForChild("Errors"))
local HttpClient = require(script.Parent:WaitForChild("HttpClient"))
local DataStoreModule = require(script.Parent:WaitForChild("DataStore"))

export type DataStore = DataStoreModule.DataStore
export type DataStoreError = Errors.DataStoreError

export type SolarchDataStoreService = {
	GetDataStore: (self: SolarchDataStoreService, name: string, scope: string?) -> DataStore,
	GetGlobalDataStore: (self: SolarchDataStoreService) -> DataStore,
	RefreshSession: (self: SolarchDataStoreService) -> (),
	GetHttpClient: (self: SolarchDataStoreService) -> any,
	GetUniverseId: (self: SolarchDataStoreService) -> number,
	IsConfigured: (self: SolarchDataStoreService) -> (boolean, string?),
	Errors: typeof(Errors),
}

local SolarchDataStoreService = {} :: SolarchDataStoreService
SolarchDataStoreService.__index = SolarchDataStoreService

local client = HttpClient.new({
	apiUrl = Config.GetApiUrl(),
	apiKey = Config.ApiKey,
	universeId = Config.GetUniverseId(),
	sessionRefreshBuffer = Config.SessionRefreshBuffer,
	maxRetries = Config.MaxRetries,
	retryBaseDelay = Config.RetryBaseDelay,
	debug = Config.Debug,
})

local instanceCache: { [string]: DataStore } = {}

local function cacheKey(name: string, scope: string): string
	return `{scope}::{name}`
end

function SolarchDataStoreService:GetDataStore(name: string, scope: string?): DataStore
	assert(typeof(name) == "string" and name ~= "", "DataStore name must be a non-empty string")
	local ok, errMsg = Config.IsConfigured()
	if not ok then
		error(Errors.toString(Errors.new("ConfigError", errMsg or "Configuration error")), 2)
	end

	local resolvedScope = scope or Config.DefaultScope
	if Config.CacheDataStoreInstances then
		local key = cacheKey(name, resolvedScope)
		local cached = instanceCache[key]
		if cached then
			return cached
		end
	end

	local ds = DataStoreModule.new({
		httpClient = client,
		scope = resolvedScope,
		namePrefix = name,
		debug = Config.Debug,
		deepCopyOnRead = Config.DeepCopyOnRead,
		updateAsyncMaxRetries = Config.UpdateAsyncMaxRetries,
	})

	if Config.CacheDataStoreInstances then
		instanceCache[cacheKey(name, resolvedScope)] = ds
	end

	return ds
end

function SolarchDataStoreService:GetGlobalDataStore(): DataStore
	return self:GetDataStore("Global", Config.DefaultScope)
end

function SolarchDataStoreService:RefreshSession()
	client:RefreshSession()
end

function SolarchDataStoreService:GetHttpClient()
	return client
end

function SolarchDataStoreService:GetUniverseId(): number
	return Config.GetUniverseId()
end

function SolarchDataStoreService:IsConfigured(): (boolean, string?)
	return Config.IsConfigured()
end

SolarchDataStoreService.Errors = Errors

return SolarchDataStoreService
