--!strict
-- Client chunk streaming: reparent between MapAssets and Workspace.DynamicMap (no clones).
-- Stream-out uses a bigger radius so chunks don't flicker at the edge.

local RENDER_RADIUS = 300
local STREAM_OUT_BUFFER = 50
local CHECK_INTERVAL = 0.5
local UNLOAD_RADIUS = RENDER_RADIUS + STREAM_OUT_BUFFER

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local mapAssets: Folder
local dynamicMap: Folder

local chunks: { [string]: Model } = {}
local loadedChunks: { [string]: Model } = {}
local lastTick = 0

local function getPlayerPosition(): Vector3?
	local char = player.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end
	return nil
end

local function refreshChunkList()
	table.clear(chunks)
	for _, child in mapAssets:GetChildren() do
		if child:IsA("Model") then
			chunks[child.Name] = child
		end
	end
end

local function updateStreaming()
	local t = os.clock()
	if t - lastTick < CHECK_INTERVAL then
		return
	end
	lastTick = t

	local pos = getPlayerPosition()
	if not pos then
		return
	end

	for _, chunk in chunks do
		local dist = (chunk:GetPivot().Position - pos).Magnitude
		if dist < RENDER_RADIUS and not loadedChunks[chunk.Name] then
			chunk.Parent = dynamicMap
			loadedChunks[chunk.Name] = chunk
		end
	end

	local toUnload = {}
	for name, chunk in loadedChunks do
		local dist = (chunk:GetPivot().Position - pos).Magnitude
		if dist > UNLOAD_RADIUS then
			table.insert(toUnload, name)
		end
	end

	for _, name in toUnload do
		local chunk = loadedChunks[name]
		if not chunk then
			continue
		end
		chunk.Parent = mapAssets
		-- clear loaded ref so this table doesn't grow forever; chunk still lives in `chunks`
		loadedChunks[name] = nil
	end
end

-- setup
local found = Workspace:FindFirstChild("DynamicMap")
if found and found:IsA("Folder") then
	dynamicMap = found
else
	dynamicMap = Instance.new("Folder")
	dynamicMap.Name = "DynamicMap"
	dynamicMap.Parent = Workspace
end

mapAssets = ReplicatedStorage:WaitForChild("MapAssets") :: Folder
refreshChunkList()

mapAssets.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		chunks[child.Name] = child
	end
end)

mapAssets.ChildRemoved:Connect(function(child)
	if not child:IsA("Model") then
		return
	end
	local c = chunks[child.Name]
	chunks[child.Name] = nil
	loadedChunks[child.Name] = nil
	if c and c.Parent ~= mapAssets then
		c.Parent = mapAssets
	end
end)

player.CharacterAdded:Connect(function()
	task.defer(function()
		lastTick = 0
		updateStreaming()
	end)
end)

RunService.Heartbeat:Connect(updateStreaming)

local n = 0
for _ in chunks do
	n += 1
end
print(`[ChunkRenderer] running — {n} chunks, load<{RENDER_RADIUS} unload>{UNLOAD_RADIUS}`)
