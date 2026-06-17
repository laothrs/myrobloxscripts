--!strict
--[[
	Per-key async queue — serializes mutations on the same key to prevent
	race conditions (mirrors Roblox DataStore ordering guarantees per key).
]]

export type KeyQueue = {
	Enqueue: <T>(self: KeyQueue, key: string, operation: () -> T) -> T,
	Clear: (self: KeyQueue, key: string?) -> (),
}

local KeyQueue = {}
KeyQueue.__index = KeyQueue

type QueueEntry = {
	running: boolean,
	pending: { () -> () },
}

function KeyQueue.new(): KeyQueue
	local self = setmetatable({}, KeyQueue)
	self._queues = {} :: { [string]: QueueEntry }
	return self
end

function KeyQueue:_getOrCreate(key: string): QueueEntry
	local entry = self._queues[key]
	if entry then
		return entry
	end
	entry = { running = false, pending = {} }
	self._queues[key] = entry
	return entry
end

function KeyQueue:_drain(key: string, entry: QueueEntry)
	if entry.running then
		return
	end
	local nextFn = table.remove(entry.pending, 1)
	if not nextFn then
		self._queues[key] = nil
		return
	end
	entry.running = true
	task.spawn(function()
		local ok, err = pcall(nextFn)
		entry.running = false
		if not ok then
			warn(`[KeyQueue] Operation failed for "{key}": {err}`)
		end
		self:_drain(key, entry)
	end)
end

function KeyQueue:Enqueue<T>(key: string, operation: () -> T): T
	local finished = false
	local result: any = nil
	local thrown: any = nil

	local entry = self:_getOrCreate(key)
	table.insert(entry.pending, function()
		local ok, value = pcall(operation)
		if ok then
			result = value
		else
			thrown = value
		end
		finished = true
	end)
	self:_drain(key, entry)

	while not finished do
		task.wait()
	end

	if thrown ~= nil then
		error(thrown, 2)
	end

	return result
end

function KeyQueue:Clear(key: string?)
	if key then
		self._queues[key] = nil
	else
		table.clear(self._queues)
	end
end

return KeyQueue
