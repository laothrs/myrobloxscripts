--!strict
local HttpService = game:GetService("HttpService")
local Errors = require(script.Parent:WaitForChild("Errors"))
local KeyQueue = require(script.Parent:WaitForChild("KeyQueue"))
local Util = require(script.Parent:WaitForChild("Util"))

export type GetOptions = {
	UseCache: boolean?,
}

export type DataStore = {
	GetAsync: (self: DataStore, key: string, options: GetOptions?) -> any?,
	SetAsync: (self: DataStore, key: string, value: any, userIds: { number }?) -> (),
	UpdateAsync: (self: DataStore, key: string, transform: (any?) -> any?, userIds: { number }?) -> any?,
	RemoveAsync: (self: DataStore, key: string) -> (),
	IncrementAsync: (self: DataStore, key: string, delta: number?, userIds: { number }?) -> number,
	GetVersionAsync: (self: DataStore, key: string) -> string?,
	InvalidateCache: (self: DataStore, key: string?) -> (),
}

export type DataStoreOptions = {
	httpClient: any,
	scope: string,
	namePrefix: string,
	debug: boolean,
	deepCopyOnRead: boolean,
	updateAsyncMaxRetries: number,
}

local DataStore = {}
DataStore.__index = DataStore

local function encodeSegment(value: string): string
	return HttpService:UrlEncode(value)
end

local function fullKey(prefix: string, key: string): string
	if prefix == "" then
		return key
	end
	return `{prefix}/{key}`
end

local function assertKey(key: string)
	local valid, reason = Util.isValidKey(key)
	if not valid then
		error(Errors.toString(Errors.new("InvalidKey", reason or "Invalid key")), 2)
	end
end

local function raiseIfError(err: Errors.DataStoreError?)
	if err then
		error(Errors.toString(err), 2)
	end
end

local function isVersionConflict(err: Errors.DataStoreError?): boolean
	if not err then
		return false
	end
	return err.StatusCode == 400 and string.find(err.Message, "DS_TAMPER") ~= nil
		or string.find(err.Message, "TAMPER") ~= nil
		or string.find(err.Message, "version") ~= nil
end

function DataStore.new(options: DataStoreOptions): DataStore
	local self = setmetatable({}, DataStore)
	self._client = options.httpClient
	self._scope = options.scope
	self._prefix = options.namePrefix
	self._debug = options.debug
	self._deepCopyOnRead = options.deepCopyOnRead
	self._updateMaxRetries = options.updateAsyncMaxRetries
	self._cache = {} :: { [string]: any }
	self._cacheLoaded = {} :: { [string]: boolean }
	self._versions = {} :: { [string]: number? }
	self._queue = KeyQueue.new()
	return self
end

function DataStore:_path(key: string): string
	return `/api/v2/datastore/{encodeSegment(self._scope)}/{encodeSegment(fullKey(self._prefix, key))}`
end

function DataStore:_log(message: string)
	if self._debug then
		print(`[SolarchDataStore/{self._prefix}] {message}`)
	end
end

function DataStore:_maybeCopy<T>(value: T): T
	if self._deepCopyOnRead and typeof(value) == "table" then
		return Util.deepCopy(value)
	end
	return value
end

function DataStore:_parseGetResult(result: any?): any?
	if result == nil then
		return nil
	end
	if result.payload ~= nil then
		return result.payload
	end
	if result.value == nil then
		return nil
	end
	return result.value
end

function DataStore:_applyGetResult(key: string, result: any?): any?
	local value = self:_parseGetResult(result)
	if result and result.version then
		self._versions[key] = result.version
	end
	self._cache[key] = value
	self._cacheLoaded[key] = true
	return self:_maybeCopy(value)
end

function DataStore:InvalidateCache(key: string?)
	if key then
		self._cache[key] = nil
		self._cacheLoaded[key] = false
		self._versions[key] = nil
	else
		table.clear(self._cache)
		table.clear(self._cacheLoaded)
		table.clear(self._versions)
	end
end

function DataStore:_fetchRemote(key: string): any?
	local result, err = self._client:Request("GET", self:_path(key))
	raiseIfError(err)
	return self:_applyGetResult(key, result)
end

function DataStore:GetAsync(key: string, options: GetOptions?): any?
	assertKey(key)

	if options and options.UseCache == false then
		self:InvalidateCache(key)
	elseif self._cacheLoaded[key] then
		return self:_maybeCopy(self._cache[key])
	end

	return self:_fetchRemote(key)
end

function DataStore:_write(
	key: string,
	method: string,
	payload: any?,
	pathSuffix: string?
): (any?, Errors.DataStoreError?)
	local path = if pathSuffix then `{self:_path(key)}{pathSuffix}` else self:_path(key)
	local body = if payload ~= nil then payload else nil
	return self._client:Request(method, path, body)
end

function DataStore:SetAsync(key: string, value: any, _userIds: { number }?): ()
	assertKey(key)
	self._queue:Enqueue(key, function()
		local body: { key: string, scope: string, payload: any, expectedVersion: number? } = {
			key = fullKey(self._prefix, key),
			scope = self._scope,
			payload = value,
		}
		local version = self._versions[key]
		if version then
			body.expectedVersion = version
		end

		local result, err = self:_write(key, "POST", body)
		raiseIfError(err)

		if result and result.newVersion then
			self._versions[key] = result.newVersion
		end
		self._cache[key] = value
		self._cacheLoaded[key] = true
		self:_log(`SetAsync "{key}"`)
	end)
end

function DataStore:UpdateAsync(key: string, transform: (any?) -> any?, _userIds: { number }?): any?
	assertKey(key)

	return self._queue:Enqueue(key, function()
		for attempt = 1, self._updateMaxRetries do
			self:InvalidateCache(key)
			local current = self:_fetchRemote(key)
			local updated = transform(current)

			if updated == nil then
				return self:_maybeCopy(current)
			end

			local body: { key: string, scope: string, payload: any, expectedVersion: number? } = {
				key = fullKey(self._prefix, key),
				scope = self._scope,
				payload = updated,
			}
			local version = self._versions[key]
			if version then
				body.expectedVersion = version
			end

			local result, err = self:_write(key, "PUT", body)
			if err and isVersionConflict(err) and attempt < self._updateMaxRetries then
				self:_log(`UpdateAsync "{key}" version conflict — retry {attempt}/{self._updateMaxRetries}`)
				task.wait(0.1 * attempt)
				continue
			end
			raiseIfError(err)

			if result and result.newVersion then
				self._versions[key] = result.newVersion
			end
			self._cache[key] = updated
			self._cacheLoaded[key] = true
			self:_log(`UpdateAsync "{key}"`)
			return self:_maybeCopy(updated)
		end

		error(Errors.toString(Errors.new("InternalError", "UpdateAsync failed after version retries")), 2)
	end)
end

function DataStore:RemoveAsync(key: string): ()
	assertKey(key)
	self._queue:Enqueue(key, function()
		local _, err = self:_write(key, "DELETE")
		raiseIfError(err)
		self:InvalidateCache(key)
		self:_log(`RemoveAsync "{key}"`)
	end)
end

function DataStore:IncrementAsync(key: string, delta: number?, _userIds: { number }?): number
	assertKey(key)

	return self._queue:Enqueue(key, function()
		self:InvalidateCache(key)
		local _, err = self:_write(key, "POST", { delta = delta or 1 }, "/increment")
		raiseIfError(err)

		local value = self:_fetchRemote(key)
		if typeof(value) == "number" then
			return value
		end
		return 0
	end)
end

function DataStore:GetVersionAsync(key: string): string?
	assertKey(key)

	if self._versions[key] then
		return tostring(self._versions[key])
	end

	local result, err = self._client:Request("GET", self:_path(key))
	if err or result == nil then
		return nil
	end
	if result.version then
		self._versions[key] = result.version
		return tostring(result.version)
	end
	return nil
end

return DataStore
