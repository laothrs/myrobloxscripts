--!strict
local HttpService = game:GetService("HttpService")
local Errors = require(script.Parent:WaitForChild("Errors"))

export type DataStore = {
	GetAsync: (self: DataStore, key: string, options: { UseCache: boolean? }?) -> any?,
	SetAsync: (self: DataStore, key: string, value: any, userIds: { number }?) -> (),
	UpdateAsync: (self: DataStore, key: string, transform: (any?) -> any?, userIds: { number }?) -> any?,
	RemoveAsync: (self: DataStore, key: string) -> (),
	IncrementAsync: (self: DataStore, key: string, delta: number?, userIds: { number }?) -> number,
	GetVersionAsync: (self: DataStore, key: string) -> string?,
}

export type DataStoreOptions = {
	httpClient: any,
	scope: string,
	namePrefix: string,
	debug: boolean,
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
	if typeof(key) ~= "string" or key == "" then
		error(Errors.toString(Errors.new("InvalidKey", "Key boş olamaz veya string olmalı")), 2)
	end
	if #key > 256 then
		error(Errors.toString(Errors.new("InvalidKey", "Key 256 karakterden uzun olamaz")), 2)
	end
end

local function raiseIfError(err: Errors.DataStoreError?)
	if err then
		error(Errors.toString(err), 2)
	end
end

function DataStore.new(options: DataStoreOptions): DataStore
	local self = setmetatable({}, DataStore)
	self._client = options.httpClient
	self._scope = options.scope
	self._prefix = options.namePrefix
	self._debug = options.debug
	self._cache = {} :: { [string]: any }
	self._cacheLoaded = {} :: { [string]: boolean }
	self._versions = {} :: { [string]: number? }
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

function DataStore:_parseGetResult(result: any?): any?
	if result == nil then
		return nil
	end
	-- Backend: { value: null } veya tam entry { payload, version, ... }
	if result.payload ~= nil then
		return result.payload
	end
	if result.value == nil then
		return nil
	end
	return result.value
end

function DataStore:GetAsync(key: string, options: { UseCache: boolean? }?): any?
	assertKey(key)

	if options and options.UseCache == false then
		self._cacheLoaded[key] = false
	elseif self._cacheLoaded[key] then
		return self._cache[key]
	end

	local result, err = self._client:Request("GET", self:_path(key))
	raiseIfError(err)

	local value = self:_parseGetResult(result)
	if result and result.version then
		self._versions[key] = result.version
	end

	self._cache[key] = value
	self._cacheLoaded[key] = true
	return value
end

function DataStore:SetAsync(key: string, value: any, _userIds: { number }?): ()
	assertKey(key)

	local body: { key: string, scope: string, payload: any, expectedVersion: number? } = {
		key = fullKey(self._prefix, key),
		scope = self._scope,
		payload = value,
	}
	local version = self._versions[key]
	if version then
		body.expectedVersion = version
	end

	local result, err = self._client:Request("POST", self:_path(key), body)
	raiseIfError(err)

	if result and result.newVersion then
		self._versions[key] = result.newVersion
	end

	self._cache[key] = value
	self._cacheLoaded[key] = true
	self:_log(`SetAsync "{key}"`)
end

function DataStore:UpdateAsync(key: string, transform: (any?) -> any?, _userIds: { number }?): any?
	assertKey(key)

	local current = self:GetAsync(key)
	local updated = transform(current)

	-- Roblox: transform nil dönerse güncelleme iptal
	if updated == nil then
		return current
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

	local result, err = self._client:Request("PUT", self:_path(key), body)
	raiseIfError(err)

	if result and result.newVersion then
		self._versions[key] = result.newVersion
	end

	self._cache[key] = updated
	self._cacheLoaded[key] = true
	self:_log(`UpdateAsync "{key}"`)
	return updated
end

function DataStore:RemoveAsync(key: string): ()
	assertKey(key)

	local _, err = self._client:Request("DELETE", self:_path(key))
	raiseIfError(err)

	self._cache[key] = nil
	self._cacheLoaded[key] = false
	self._versions[key] = nil
	self:_log(`RemoveAsync "{key}"`)
end

function DataStore:IncrementAsync(key: string, delta: number?, _userIds: { number }?): number
	assertKey(key)

	self._cacheLoaded[key] = false

	local _, err = self._client:Request("POST", `{self:_path(key)}/increment`, {
		delta = delta or 1,
	})
	raiseIfError(err)

	local value = self:GetAsync(key, { UseCache = false })
	if typeof(value) == "number" then
		return value
	end
	return 0
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
