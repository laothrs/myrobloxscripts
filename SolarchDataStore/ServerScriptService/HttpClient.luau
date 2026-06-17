--!strict
local HttpService = game:GetService("HttpService")
local Errors = require(script.Parent:WaitForChild("Errors"))

export type HttpClient = {
	Request: (self: HttpClient, method: string, path: string, body: any?) -> (any?, Errors.DataStoreError?),
	RefreshSession: (self: HttpClient) -> (),
	GetSessionToken: (self: HttpClient) -> (string?, Errors.DataStoreError?),
}

local HttpClient = {}
HttpClient.__index = HttpClient

export type HttpClientOptions = {
	apiUrl: string,
	apiKey: string,
	universeId: number,
	sessionRefreshBuffer: number,
	maxRetries: number,
	retryBaseDelay: number,
	debug: boolean,
}

local function log(debug: boolean, message: string)
	if debug then
		print(`[SolarchDataStore] {message}`)
	end
end

function HttpClient.new(options: HttpClientOptions): HttpClient
	local self = setmetatable({}, HttpClient)
	self._options = options
	self._apiUrl = options.apiUrl
	self._sessionToken = nil :: string?
	self._sessionExpiresAt = 0
	self._refreshing = false
	return self
end

function HttpClient:RefreshSession()
	self._sessionToken = nil
	self._sessionExpiresAt = 0
end

function HttpClient:GetSessionToken(): (string?, Errors.DataStoreError?)
	if self._sessionToken and os.clock() < self._sessionExpiresAt then
		return self._sessionToken, nil
	end

	if self._options.universeId <= 0 then
		return nil, Errors.new(
			"ConfigError",
			"Invalid UniverseId — set Config.UniverseId or Config.StudioUniverseId (GameId is 0 in Studio)."
		)
	end

	while self._refreshing do
		task.wait()
	end

	if self._sessionToken and os.clock() < self._sessionExpiresAt then
		return self._sessionToken, nil
	end

	self._refreshing = true

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = `{self._apiUrl}/api/v2/session`,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["x-api-key"] = self._options.apiKey,
			},
			Body = HttpService:JSONEncode({
				universeId = self._options.universeId,
				scopes = { "datastore:read", "datastore:write" },
			}),
		})
	end)

	self._refreshing = false

	if not ok then
		return nil, Errors.new("NetworkError", tostring(response))
	end

	if not response.Success then
		return nil, Errors.fromHttpStatus(response.StatusCode, response.Body)
	end

	local decodeOk, body = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	if not decodeOk or typeof(body) ~= "table" or body.accessToken == nil then
		return nil, Errors.new("InternalError", "Invalid session response")
	end

	self._sessionToken = body.accessToken
	self._sessionExpiresAt = os.clock() + (body.expiresIn or 300) - self._options.sessionRefreshBuffer
	log(self._options.debug, "Session token acquired")
	return self._sessionToken, nil
end

function HttpClient:_backoff(attempt: number, statusCode: number?): number
	local base = self._options.retryBaseDelay * attempt
	if statusCode == 429 then
		return base * 3
	end
	if statusCode and statusCode >= 500 then
		return base * 2
	end
	return base
end

function HttpClient:Request(method: string, path: string, body: any?): (any?, Errors.DataStoreError?)
	local lastError: Errors.DataStoreError? = nil

	for attempt = 1, self._options.maxRetries do
		local token, sessionErr = self:GetSessionToken()
		if not token then
			lastError = sessionErr
			task.wait(self._options.retryBaseDelay * attempt)
			continue
		end

		local req: { Url: string, Method: string, Headers: { [string]: string }, Body: string? } = {
			Url = `{self._apiUrl}{path}`,
			Method = method,
			Headers = {
				["Content-Type"] = "application/json",
				["Authorization"] = `Bearer {token}`,
			},
		}

		if body ~= nil then
			req.Body = HttpService:JSONEncode(body)
		end

		local ok, response = pcall(function()
			return HttpService:RequestAsync(req)
		end)

		if not ok then
			lastError = Errors.new("NetworkError", tostring(response))
			task.wait(self._options.retryBaseDelay * attempt)
			continue
		end

		if not response.Success then
			if response.StatusCode == 401 then
				self:RefreshSession()
				task.wait(self._options.retryBaseDelay * attempt)
				continue
			end

			if response.StatusCode == 429 or response.StatusCode >= 500 then
				lastError = Errors.fromHttpStatus(response.StatusCode, response.Body)
				task.wait(self:_backoff(attempt, response.StatusCode))
				continue
			end

			return nil, Errors.fromHttpStatus(response.StatusCode, response.Body)
		end

		if response.Body == "" or response.StatusCode == 204 then
			return nil, nil
		end

		local decodeOk, decoded = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		if not decodeOk then
			return nil, Errors.new("InternalError", "JSON decode failed")
		end

		return decoded, nil
	end

	return nil, lastError or Errors.new("NetworkError", "Request failed after all retries")
end

return HttpClient
