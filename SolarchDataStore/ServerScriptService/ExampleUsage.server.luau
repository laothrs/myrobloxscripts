--!strict
--[[
	Example — PlayerDataManager integration (recommended production path).
	Enable this Script (Disabled = false) after configuring Config.
]]

local PlayerDataManager = require(script.Parent:WaitForChild("PlayerDataManager"))

PlayerDataManager.Init()

-- Gameplay example:
-- local coins = PlayerDataManager.Get(player, "Coins")
-- PlayerDataManager.Increment(player, "Coins", 50)
