--!strict
--[[
	Setup Validator — sunucu başlangıcında yapılandırma ve bağlantı testi.
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent:WaitForChild("Config"))

local function warnMsg(title: string, detail: string)
	warn(`[SolarchDataStore] ⚠ {title}`)
	warn(`  → {detail}`)
end

local function validate()
	if not RunService:IsServer() then
		return
	end

	if not HttpService.HttpEnabled then
		warnMsg("HttpService kapalı", "Game Settings → Security → Allow HTTP Requests")
		return
	end

	local configured, configErr = Config.IsConfigured()
	if not configured then
		warnMsg("Yapılandırma eksik", configErr or "Config modülünü kontrol edin")
		return
	end

	local universeId = Config.GetUniverseId()
	if universeId <= 0 then
		warnMsg(
			"UniverseId bulunamadı",
			"Studio test için Config.StudioUniverseId veya Config.UniverseId ayarlayın"
		)
		return
	end

	if not Config.RunSetupValidator then
		return
	end

	task.defer(function()
		local apiUrl = Config.GetApiUrl()
		local ok, result = pcall(function()
			return HttpService:RequestAsync({
				Url = `{apiUrl}/api/v2/session`,
				Method = "POST",
				Headers = {
					["Content-Type"] = "application/json",
					["x-api-key"] = Config.ApiKey,
				},
				Body = HttpService:JSONEncode({
					universeId = universeId,
					scopes = { "datastore:read", "datastore:write" },
				}),
			})
		end)

		if not ok then
			warnMsg("Backend'e bağlanılamadı", tostring(result))
			return
		end

		if not result.Success then
			warnMsg("Backend oturum hatası", `HTTP {result.StatusCode}: {result.Body}`)
			return
		end

		if Config.Debug then
			print(`[SolarchDataStore] ✓ Kurulum OK — universe {universeId}, backend {apiUrl}`)
		end
	end)
end

validate()
