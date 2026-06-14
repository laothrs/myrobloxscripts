--[[
  ╔══════════════════════════════════════════════════════════════╗
  ║           SOLARCH DATASTORE — ROBLOX STUDIO KURULUM          ║
  ╚══════════════════════════════════════════════════════════════╝

  ADIM 1 — Backend
  • npm install && cp .env.example .env && npm run db:migrate && npm start

  ADIM 2 — Studio'ya aktarma
  • npm run build:roblox
  • File → Insert from File → roblox/dist/SolarchDataStore.rbxmx
  • SolarchDataStore klasörünü ServerScriptService'e taşıyın

  ADIM 3 — Config (SolarchDataStore → Config)
  • Config.ApiUrl  = backend URL (https://... production'da)
  • Config.ApiKey  = .env ROBLOX_API_KEY
  • Config.StudioUniverseId = test universe ID (Studio'da GameId 0 ise)

  ADIM 4 — HttpService
  • Game Settings → Security → Allow HTTP Requests ✓

  ADIM 5 — Kullanım
  local DataStoreService = require(
    game.ServerScriptService.SolarchDataStore.SolarchDataStore
  )
  local store = DataStoreService:GetDataStore("PlayerData")
  store:SetAsync("key", { coins = 100 })

  API: GetAsync, SetAsync, UpdateAsync, RemoveAsync, IncrementAsync, GetVersionAsync
  Hatalar: pcall ile yakalayın veya Errors modülünü inceleyin
]]

return nil
