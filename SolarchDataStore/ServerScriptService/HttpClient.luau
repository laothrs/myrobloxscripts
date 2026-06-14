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
			"UniverseId geçersiz. Config.UniverseId veya Config.StudioUniverseId ayarlayın (Studio'da GameId 0 olabilir)."
		)
	end

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
		return nil, Errors.new("InternalError", "Session yanıtı geçersiz")
	end

	self._sessionToken = body.accessToken
	self._sessionExpiresAt = os.clock() + (body.expiresIn or 300) - self._options.sessionRefreshBuffer
	log(self._options.debug, "Session token alındı")
	return self._sessionToken, nil
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
				task.wait(self._options.retryBaseDelay * attempt * 2)
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
			return nil, Errors.new("InternalError", "JSON çözümleme hatası")
		end

		return decoded, nil
	end

	return nil, lastError or Errors.new("NetworkError", "İstek tüm denemelerden sonra başarısız oldu")
end

return HttpClient
