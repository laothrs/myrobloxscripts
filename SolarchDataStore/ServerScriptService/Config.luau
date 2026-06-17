--!strict
--[[
	Solarch DataStore — Configuration
	Edit this file only; all other modules read from here.
]]

export type ConfigTable = {
	ApiUrl: string,
	ApiKey: string,
	UniverseId: number?,
	DefaultScope: string,
	SessionRefreshBuffer: number,
	MaxRetries: number,
	RetryBaseDelay: number,
	RequestTimeout: number,
	UpdateAsyncMaxRetries: number,
	DeepCopyOnRead: boolean,
	CacheDataStoreInstances: boolean,
	Debug: boolean,
	RunSetupValidator: boolean,
	StudioUniverseId: number,
	GetUniverseId: (self: ConfigTable) -> number,
	IsConfigured: (self: ConfigTable) -> (boolean, string?),
	GetApiUrl: (self: ConfigTable) -> string,
}

local Config: ConfigTable = {
	ApiUrl = "http://localhost:3000",
	ApiKey = "YOUR_API_KEY_HERE",
	UniverseId = nil,
	DefaultScope = "global",
	SessionRefreshBuffer = 30,
	MaxRetries = 3,
	RetryBaseDelay = 0.5,
	RequestTimeout = 30,
	-- Retries on version conflict during UpdateAsync (optimistic concurrency)
	UpdateAsyncMaxRetries = 5,
	-- Return deep copies from GetAsync so callers cannot corrupt the session cache
	DeepCopyOnRead = true,
	-- Reuse DataStore instances per name+scope (Roblox DataStoreService behavior)
	CacheDataStoreInstances = true,
	Debug = true,
	RunSetupValidator = true,
	StudioUniverseId = 0,
} :: any

function Config.GetUniverseId(): number
	if Config.UniverseId and Config.UniverseId > 0 then
		return Config.UniverseId
	end
	if game.GameId > 0 then
		return game.GameId
	end
	if Config.StudioUniverseId > 0 then
		return Config.StudioUniverseId
	end
	return 0
end

function Config.IsConfigured(): (boolean, string?)
	if Config.ApiKey == "" or Config.ApiKey == "YOUR_API_KEY_HERE" then
		return false, "Config.ApiKey is not set"
	end
	if Config.ApiUrl == "" then
		return false, "Config.ApiUrl is not set"
	end
	if string.find(Config.ApiUrl, "YOUR") then
		return false, "Config.ApiUrl is invalid"
	end
	return true, nil
end

function Config.GetApiUrl(): string
	local url = Config.ApiUrl
	if string.sub(url, -1) == "/" then
		return string.sub(url, 1, -2)
	end
	return url
end

return Config
