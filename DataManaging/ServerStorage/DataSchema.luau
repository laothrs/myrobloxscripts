--!strict
--[[
	DataSchema
	──────────
	Default player data template for session / DataStore reconciliation.
	Place under ServerStorage in a live game; this repo is portfolio source only.

	Usage:
		local DataSchema = require(ServerStorage.DataSchema)
		local data = DataSchema.GetDefault()
]]

export type PlayerStats = {
	Kills: number,
	Deaths: number,
}

export type Inventory = { [string]: number }

export type PlayerData = {
	Coins: number,
	Level: number,
	Experience: number,
	Inventory: Inventory,
	Stats: PlayerStats,
}

local DEFAULT_STATS: PlayerStats = {
	Kills = 0,
	Deaths = 0,
}

local DEFAULT_INVENTORY: Inventory = {}

local DEFAULT_PLAYER_DATA: PlayerData = {
	Coins = 0,
	Level = 1,
	Experience = 0,
	Inventory = DEFAULT_INVENTORY,
	Stats = DEFAULT_STATS,
}

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

local DataSchema = {
	Stats = DEFAULT_STATS,
	Inventory = DEFAULT_INVENTORY,
	Default = DEFAULT_PLAYER_DATA,
}

function DataSchema.GetDefault(): PlayerData
	return deepCopy(DEFAULT_PLAYER_DATA)
end

return DataSchema
