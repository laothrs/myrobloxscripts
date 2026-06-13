-- Discord: [YOUR_DISCORD_USERNAME] | Roblox: [YOUR_ROBLOX_USERNAME]
--!strict
--!optimize 2

--[[
	MapChunkRenderer (client)

	Streams map chunks in and out around the player. The server keeps every
	chunk Model parked in ReplicatedStorage.MapAssets - stuff in there gets
	replicated to the client but isn't rendered or simulated, so it works as
	free "cold storage". To show a chunk we just reparent it into
	Workspace.DynamicMap, and to hide it we move it back. No cloning at all,
	which keeps memory flat and means the server's references stay valid.

	Rough layout: config at the top, then a Chunk class (one instance per
	model, owns its own load/unload/destroy lifecycle plus a little reveal
	animation), then the manager loop at the bottom that decides *when* each
	chunk should load based on distance + a cheap frustum check.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

---------------------------------------------------------------- config

-- grid cell size in studs, only used to derive (chunkX, chunkZ) coords
local CHUNK_SIZE = 100

-- load inside this radius...
local RENDER_RADIUS = 300

-- ...but only unload once we're this far PAST it. The gap is hysteresis -
-- without it, chunks sitting right on the boundary flicker in and out as
-- the player strafes along the edge.
local STREAM_OUT_BUFFER = 50
local UNLOAD_RADIUS = RENDER_RADIUS + STREAM_OUT_BUFFER

-- streaming decisions run at most this often. Half a second is invisible
-- to the player and saves us ~30 distance scans per second.
local CHECK_INTERVAL = 0.5

-- Frustum gate threshold. We compare the dot product of the camera's
-- LookVector against the direction to the chunk; since both are unit
-- vectors, the dot IS the cosine of the angle between them. -0.2 gives
-- roughly a 200 degree forward cone, so peripheral chunks still load and
-- only stuff properly behind the camera gets deferred.
local FRUSTUM_DOT_THRESHOLD = -0.2

-- chunks this close always render, even behind the camera. Otherwise the
-- ground under your feet could get deferred just because you turned around.
local NEAR_RENDER_RADIUS = CHUNK_SIZE * 1.5

-- reveal animation: rise from RISE_OFFSET studs below while fading in
local RISE_OFFSET = 5
local ANIMATION_TIME = 0.45
local EASING_STYLE = Enum.EasingStyle.Quad
local EASING_DIRECTION = Enum.EasingDirection.Out

local player = Players.LocalPlayer

-- both resolved in the setup block at the bottom
local mapAssets: Folder
local dynamicMap: Folder

---------------------------------------------------------------- Chunk class

-- Standard Luau metatable class. __index = Chunk means method lookups fall
-- through to this shared table, so there's exactly one copy of each method
-- no matter how many chunks exist, and creating one is a single table alloc.
local Chunk = {}
Chunk.__index = Chunk

export type Chunk = typeof(setmetatable(
	{} :: {
		chunkX: number, -- grid column, floor(pivot.X / CHUNK_SIZE)
		chunkZ: number, -- grid row
		model: Model,
		name: string, -- mirrors model.Name, used as the registry key
		restingPivot: CFrame, -- canonical pivot, captured once at construction
		position: Vector3, -- cached pivot position for distance checks
		loaded: boolean,
		destroyed: boolean,
		animationToken: number, -- bumping this cancels any running animation
	},
	Chunk
))

-- The pivot gets captured once here and never re-read. The reveal animation
-- always converges back to it, so load/unload churn can't accumulate drift.
function Chunk.new(chunkX: number, chunkZ: number, model: Model): Chunk
	local restingPivot = model:GetPivot()

	local self = setmetatable({
		chunkX = chunkX,
		chunkZ = chunkZ,
		model = model,
		name = model.Name,
		restingPivot = restingPivot,
		position = restingPivot.Position,
		loaded = false,
		destroyed = false,
		animationToken = 0,
	}, Chunk)

	return self :: Chunk
end

-- Factory that figures out the grid cell from world position. floor(x/size)
-- maps continuous space onto the grid (with size 100, X in [200,300) is
-- column 2), and since floor rounds toward -inf it stays seamless across
-- the origin for negative coords too.
function Chunk.fromModel(model: Model): Chunk
	local pos = model:GetPivot().Position
	return Chunk.new(
		math.floor(pos.X / CHUNK_SIZE),
		math.floor(pos.Z / CHUNK_SIZE),
		model
	)
end

function Chunk.GetDistanceTo(self: Chunk, point: Vector3): number
	return (self.position - point).Magnitude
end

-- The frustum check. Normalize the offset to the chunk, dot it with the
-- camera look direction, compare against the cone threshold. Three mults
-- and two adds - way cheaper than WorldToScreenPoint, which does a full
-- matrix projection, and plenty accurate for streaming purposes.
function Chunk.IsInView(self: Chunk, viewPosition: Vector3, lookVector: Vector3): boolean
	local offset = self.position - viewPosition
	local distance = offset.Magnitude

	-- nearby chunks skip the check entirely, see NEAR_RENDER_RADIUS note
	if distance < NEAR_RENDER_RADIUS then
		return true
	end

	-- offset/distance is the unit direction; we already paid for the sqrt
	-- in Magnitude so no point calling .Unit and doing it again
	return lookVector:Dot(offset / distance) > FRUSTUM_DOT_THRESHOLD
end

--[[
	The reveal: model starts RISE_OFFSET studs low and fully faded, then
	rises and fades in. A few deliberate choices here:

	- TweenService:GetValue() just remaps time onto the easing curve, so one
	  loop drives both the pivot lerp and the fade. No Tween instances
	  created = nothing to destroy or leak.
	- The fade uses LocalTransparencyModifier, which is client-only and sits
	  on top of the real Transparency. Glass stays glass, and cleanup is a
	  plain reset to 0 with no per-part snapshots.
	- Cancellation is a token: Unload/Destroy bump animationToken and the
	  loop bails as soon as its captured copy is stale. No connections to
	  track, no coroutine left running.
]]
function Chunk._animateIn(self: Chunk)
	self.animationToken += 1
	local token = self.animationToken

	local parts: { BasePart } = {}
	for _, descendant in self.model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = 1
			table.insert(parts, descendant)
		end
	end

	local startPivot = self.restingPivot - Vector3.new(0, RISE_OFFSET, 0)
	self.model:PivotTo(startPivot)

	task.spawn(function()
		local elapsed = 0
		while elapsed < ANIMATION_TIME do
			elapsed += RunService.Heartbeat:Wait()

			-- newer animation, unload, or destroy -> we're stale, stop
			if self.animationToken ~= token or not self.loaded then
				return
			end

			local alpha = TweenService:GetValue(
				math.min(elapsed / ANIMATION_TIME, 1),
				EASING_STYLE,
				EASING_DIRECTION
			)
			self.model:PivotTo(startPivot:Lerp(self.restingPivot, alpha))
			for _, part in parts do
				part.LocalTransparencyModifier = 1 - alpha
			end
		end

		-- snap exactly onto the resting pose at the end, just to be safe
		self.model:PivotTo(self.restingPivot)
		for _, part in parts do
			part.LocalTransparencyModifier = 0
		end
	end)
end

-- Instantly restore the clean visual state. Runs before unload/destroy so
-- a chunk caught mid-animation never goes back to storage half-sunk or
-- half-transparent.
function Chunk._resetAppearance(self: Chunk)
	self.animationToken += 1 -- kills any in-flight animation loop

	self.model:PivotTo(self.restingPivot)
	for _, descendant in self.model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = 0
		end
	end
end

-- Stream in: move to Workspace and play the reveal. Safe to call twice.
function Chunk.Render(self: Chunk)
	if self.loaded or self.destroyed then
		return
	end
	self.loaded = true
	self.model.Parent = dynamicMap
	self:_animateIn()
end

-- Stream out: back to cold storage. The model itself is NOT destroyed -
-- it's server-owned geometry and we'll probably want it again.
function Chunk.Unload(self: Chunk)
	if not self.loaded or self.destroyed then
		return
	end
	self.loaded = false
	self:_resetAppearance()
	self.model.Parent = mapAssets
end

--[[
	Permanent teardown, for when the server actually deletes a chunk.
	Leak prevention is three things working together: the token bump ends
	the animation coroutine (whose closure captures self and the parts
	array), clearing `model` stops this table from rooting the instance
	tree, and the `destroyed` latch turns any later call on a stale
	reference into a no-op. Note there are intentionally zero per-chunk
	event connections in this class - all signals live on the manager -
	so there's nothing to Disconnect here in the first place.
]]
function Chunk.Destroy(self: Chunk)
	if self.destroyed then
		return
	end

	if self.loaded then
		self.loaded = false
		self:_resetAppearance()
	else
		self.animationToken += 1
	end

	self.destroyed = true
	self.model = nil :: any -- cast needed to nil a typed field under strict
end

---------------------------------------------------------------- manager

-- every known chunk, keyed by model name (server guarantees unique names)
local registry: { [string]: Chunk } = {}

-- the loaded subset, kept separate so the unload scan only touches what's
-- actually in the world instead of the whole map
local loadedChunks: { [string]: Chunk } = {}

local lastTick = 0

-- Distance is measured from the character (the world should stream around
-- the avatar), but view direction comes from the camera, since only it
-- knows where the player is looking. Returns nil while dead/respawning -
-- streaming just pauses and loaded chunks stay put, so the death camera
-- never watches the map dissolve.
local function getViewState(): (Vector3?, Vector3?)
	local character = player.Character
	if not character then
		return nil, nil
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return nil, nil
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return nil, nil
	end

	return hrp.Position, camera.CFrame.LookVector
end

-- The main streaming pass, throttled to CHECK_INTERVAL.
-- Load rule: close enough AND passes the frustum gate.
-- Unload rule: too far, period. We deliberately ignore the frustum on
-- unload - dropping chunks just because the player looked away would mean
-- constant churn the moment they look back. A chunk that's near but behind
-- the camera isn't skipped forever either; it stays in the registry and
-- loads on a later pass once the player turns toward it.
local function updateStreaming()
	local now = os.clock()
	if now - lastTick < CHECK_INTERVAL then
		return
	end
	lastTick = now

	local viewPosition, lookVector = getViewState()
	if not (viewPosition and lookVector) then
		return
	end

	for _, chunk in registry do
		if chunk.loaded then
			continue
		end
		if chunk:GetDistanceTo(viewPosition) >= RENDER_RADIUS then
			continue
		end
		if chunk:IsInView(viewPosition, lookVector) then
			chunk:Render()
			loadedChunks[chunk.name] = chunk
		end
	end

	-- collect first, remove after - mutating a table mid-iteration is
	-- undefined behaviour in Luau
	local toUnload: { string } = {}
	for name, chunk in loadedChunks do
		if chunk:GetDistanceTo(viewPosition) > UNLOAD_RADIUS then
			table.insert(toUnload, name)
		end
	end

	for _, name in toUnload do
		local chunk = loadedChunks[name]
		loadedChunks[name] = nil -- always drop the ref so this table can't grow forever
		if chunk then
			chunk:Unload()
		end
	end
end

local function registerModel(model: Instance)
	if model:IsA("Model") then
		registry[model.Name] = Chunk.fromModel(model)
	end
end

-- ChildRemoved also fires when WE pull a model out to stream it in, so we
-- use the chunk's own `loaded` flag to tell the cases apart: if it's loaded
-- the removal was ours, otherwise the server really deleted it.
local function unregisterModel(model: Instance)
	if not model:IsA("Model") then
		return
	end

	local chunk = registry[model.Name]
	if not chunk or chunk.loaded then
		return
	end

	registry[model.Name] = nil
	loadedChunks[model.Name] = nil
	chunk:Destroy()
end

---------------------------------------------------------------- setup

do
	local found = Workspace:FindFirstChild("DynamicMap")
	if found and found:IsA("Folder") then
		dynamicMap = found
	else
		dynamicMap = Instance.new("Folder")
		dynamicMap.Name = "DynamicMap"
		dynamicMap.Parent = Workspace
	end
end

mapAssets = ReplicatedStorage:WaitForChild("MapAssets") :: Folder

for _, child in mapAssets:GetChildren() do
	registerModel(child)
end
mapAssets.ChildAdded:Connect(registerModel)
mapAssets.ChildRemoved:Connect(unregisterModel)

-- force an immediate pass on respawn so the world is there before the spawn
-- camera fades in. task.defer gives the HumanoidRootPart a beat to exist.
player.CharacterAdded:Connect(function()
	task.defer(function()
		lastTick = 0
		updateStreaming()
	end)
end)

RunService.Heartbeat:Connect(updateStreaming)

do
	local count = 0
	for _ in registry do
		count += 1
	end
	print(`[ChunkRenderer] {count} chunks indexed | load < {RENDER_RADIUS} | unload > {UNLOAD_RADIUS}`)
end
