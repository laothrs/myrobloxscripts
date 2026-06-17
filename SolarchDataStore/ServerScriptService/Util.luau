--!strict
--[[
	Shared utilities — deep copy, table merge, key validation helpers.
]]

local Util = {}

export type JSONValue = string | number | boolean | { [string]: JSONValue } | { JSONValue }

function Util.deepCopy<T>(value: T): T
	local t = typeof(value)
	if t ~= "table" then
		return value
	end
	local copy = {} :: any
	for k, v in pairs(value :: any) do
		copy[Util.deepCopy(k)] = Util.deepCopy(v)
	end
	return copy :: T
end

function Util.reconcile(data: { [string]: any }, template: { [string]: any }): { [string]: any }
	local result = Util.deepCopy(data)
	for key, defaultValue in pairs(template) do
		local current = result[key]
		if current == nil then
			result[key] = Util.deepCopy(defaultValue)
		elseif typeof(current) == "table" and typeof(defaultValue) == "table" then
			result[key] = Util.reconcile(current, defaultValue)
		end
	end
	return result
end

function Util.isValidKey(key: string): (boolean, string?)
	if typeof(key) ~= "string" or key == "" then
		return false, "Key must be a non-empty string"
	end
	if #key > 256 then
		return false, "Key must be 256 characters or fewer"
	end
	if string.find(key, "\0") then
		return false, "Key cannot contain null bytes"
	end
	return true, nil
end

function Util.trimUrl(url: string): string
	if string.sub(url, -1) == "/" then
		return string.sub(url, 1, -2)
	end
	return url
end

return Util
