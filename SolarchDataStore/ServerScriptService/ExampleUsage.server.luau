--!strict
--[[
	Örnek: Oyuncu profili kaydetme/yükleme.
	Enable etmek için Script'in Disabled özelliğini false yapın.
]]

local Players = game:GetService("Players")
local DataStoreService = require(script.Parent:WaitForChild("SolarchDataStore"))

local playerStore = DataStoreService:GetDataStore("PlayerData")

local function loadProfile(player: Player)
	local key = "profile_" .. player.UserId
	local ok, profile = pcall(function()
		return playerStore:GetAsync(key)
	end)

	if not ok then
		warn(`[Example] {player.Name} yüklenemedi: {profile}`)
		player:Kick("Veri sunucusuna bağlanılamadı. Lütfen tekrar deneyin.")
		return
	end

	if profile == nil then
		profile = { coins = 0, level = 1, lastLogin = os.time() }
		local setOk, setErr = pcall(function()
			playerStore:SetAsync(key, profile)
		end)
		if not setOk then
			warn(`[Example] Profil oluşturulamadı: {setErr}`)
			return
		end
	end

	print(`[Example] {player.Name} — coins: {profile.coins}, level: {profile.level}`)
end

local function saveProfile(player: Player)
	local key = "profile_" .. player.UserId
	pcall(function()
		playerStore:UpdateAsync(key, function(old)
			local data = old or { coins = 0, level = 1 }
			data.lastLogin = os.time()
			return data
		end)
	end)
end

Players.PlayerAdded:Connect(loadProfile)
Players.PlayerRemoving:Connect(saveProfile)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		saveProfile(player)
	end
end)
