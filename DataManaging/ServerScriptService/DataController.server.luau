--!strict
--[[
	DataController
	──────────────
	Wires player lifecycle and server shutdown to DataManager.
	Place as a Script under ServerScriptService in a live game.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("DataManager"))

local AUTO_SAVE_INTERVAL = 120
local SHUTDOWN_SAVE_TIMEOUT = 30

local function onPlayerAdded(player: Player): ()
	task.spawn(DataManager.LoadProfile, player)
end

local function onPlayerRemoving(player: Player): ()
	DataManager.ReleasePlayer(player)
end

local function saveAllPlayersOnShutdown(): ()
	local players = Players:GetPlayers()
	local pending = 0

	for _, player in players do
		if not DataManager.IsLoaded(player) then
			continue
		end

		pending += 1
		task.spawn(function()
			local ok = DataManager.SaveProfile(player)
			if not ok then
				warn(`[DataController] Shutdown save failed for {player.Name} ({player.UserId})`)
			end
			pending -= 1
		end)
	end

	local deadline = os.clock() + SHUTDOWN_SAVE_TIMEOUT
	while pending > 0 and os.clock() < deadline do
		task.wait()
	end

	if pending > 0 then
		warn(`[DataController] Shutdown save timed out with {pending} profile(s) remaining`)
	end
end

local function startAutoSave(): ()
	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)
			DataManager.SaveAll()
		end
	end)
end

game:BindToClose(function()
	saveAllPlayersOnShutdown()

	if not RunService:IsStudio() then
		task.wait(2)
	end
end)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

startAutoSave()
