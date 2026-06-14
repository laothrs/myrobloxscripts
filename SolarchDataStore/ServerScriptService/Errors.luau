--!strict
--[[
	Roblox DataStoreService uyumlu hata tipleri.
	https://create.roblox.com/docs/reference/engine/enums/DataStoreRequestType
]]

export type DataStoreErrorType =
	"InternalError"
	| "NetworkError"
	| "AuthError"
	| "RateLimitError"
	| "ConfigError"
	| "InvalidKey"
	| "NotFound"

export type DataStoreError = {
	ErrorType: DataStoreErrorType,
	Message: string,
	StatusCode: number?,
}

local Errors = {}

function Errors.new(errorType: DataStoreErrorType, message: string, statusCode: number?): DataStoreError
	return {
		ErrorType = errorType,
		Message = message,
		StatusCode = statusCode,
	}
end

function Errors.fromHttpStatus(statusCode: number, body: string?): DataStoreError
	local message = body or `HTTP {statusCode}`
	if statusCode == 401 or statusCode == 403 then
		return Errors.new("AuthError", message, statusCode)
	end
	if statusCode == 429 then
		return Errors.new("RateLimitError", message, statusCode)
	end
	if statusCode >= 500 then
		return Errors.new("InternalError", message, statusCode)
	end
	return Errors.new("NetworkError", message, statusCode)
end

function Errors.toString(err: DataStoreError): string
	return `[SolarchDataStore:{err.ErrorType}] {err.Message}`
end

return Errors
