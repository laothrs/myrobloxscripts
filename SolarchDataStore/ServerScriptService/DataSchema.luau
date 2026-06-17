--!strict
--[[
	Default player profile schema — extend for your game.
	Used by PlayerDataManager for reconciliation on load.
]]

export type PlayerStats = {
	Kills: number,
	Deaths: number,
}

export type PlayerData = {
	Coins: number,
	Level: number,
	Experience: number,
	Inventory: { [string]: number },
	Stats: PlayerStats,
	LastLogin: number,
}

local DataSchema = {}

DataSchema.DefaultProfile = {
	Coins = 0,
	Level = 1,
	Experience = 0,
	Inventory = {},
	Stats = {
		Kills = 0,
		Deaths = 0,
	},
	LastLogin = 0,
} :: PlayerData

DataSchema.DataStoreName = "PlayerData"

return DataSchema
