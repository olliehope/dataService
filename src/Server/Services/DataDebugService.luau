--!strict
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(ReplicatedStorage:WaitForChild("DataService")).server
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Networker = require(Packages:WaitForChild("Networker"))
local SaveSlotService = require(script.Parent.SaveSlotService)

local DataDebugService = {
	networker = nil :: Networker.Server?,
	_itemCounter = 0,
}

local function clampNumber(value: any, minValue: number, maxValue: number, fallback: number): number
	local numberValue = tonumber(value)
	if not numberValue then
		return fallback
	end

	return math.clamp(math.floor(numberValue), minValue, maxValue)
end

local function cloneForClient(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in value do
		copy[key] = cloneForClient(child)
	end

	return copy
end

local function encodeForPrint(value: any): string
	local success, encoded = pcall(function()
		return HttpService:JSONEncode(value)
	end)

	if success then
		return encoded
	end

	return tostring(value)
end

function DataDebugService.init(self: typeof(DataDebugService)): ()
	assert(not self.networker, "DataDebugService has already been initialized.")

	self.networker = Networker.server.new("DataDebug", self, {
		self.getSnapshot,
		self.addCurrency,
		self.addItem,
		self.levelUp,
		self.setMusic,
		self.saveNow,
		self.printSnapshot,
	})

	print("[DataDebugService] Ready. Client debug buttons are enabled after a save slot loads.")
end

function DataDebugService.getSnapshot(_self: typeof(DataDebugService), player: Player)
	if not DataService:isPlayerLoaded(player) then
		print(`[DataDebugService] {player.Name} requested snapshot before loading a slot.`)
		return {
			loaded = false,
			data = nil,
		}
	end

	local data = cloneForClient(DataService:get(player))
	print(`[DataDebugService] Snapshot requested by {player.Name}: {encodeForPrint(data)}`)

	return {
		loaded = true,
		data = data,
	}
end

function DataDebugService.addCurrency(self: typeof(DataDebugService), player: Player, amount: number?)
	if not DataService:isPlayerLoaded(player) then
		return self:_notLoaded(player)
	end

	local delta = clampNumber(amount, -100000, 100000, 25)
	local newCurrency = DataService:update(player, { "currency" }, function(current)
		return (tonumber(current) or 0) + delta
	end)

	print(`[DataDebugService] {player.Name} currency changed by {delta}. New value: {newCurrency}`)
	return self:getSnapshot(player)
end

function DataDebugService.addItem(self: typeof(DataDebugService), player: Player, itemName: string?)
	if not DataService:isPlayerLoaded(player) then
		return self:_notLoaded(player)
	end

	self._itemCounter += 1
	local item = {
		id = `debug_item_{self._itemCounter}`,
		name = if itemName and itemName ~= "" then itemName else `Debug Item {self._itemCounter}`,
		createdAt = os.time(),
	}

	DataService:arrayInsert(player, { "inventory" }, item)
	print(`[DataDebugService] Added inventory item for {player.Name}: {encodeForPrint(item)}`)

	return self:getSnapshot(player)
end

function DataDebugService.levelUp(self: typeof(DataDebugService), player: Player)
	if not DataService:isPlayerLoaded(player) then
		return self:_notLoaded(player)
	end

	local level = DataService:update(player, { "stats", "level" }, function(current)
		return (tonumber(current) or 1) + 1
	end)

	print(`[DataDebugService] {player.Name} leveled up to {level}`)
	return self:getSnapshot(player)
end

function DataDebugService.setMusic(self: typeof(DataDebugService), player: Player, value: number?)
	if not DataService:isPlayerLoaded(player) then
		return self:_notLoaded(player)
	end

	local music = clampNumber(value, 0, 100, 100)
	DataService:set(player, { "settings", "music" }, music)

	print(`[DataDebugService] {player.Name} music setting set to {music}`)
	return self:getSnapshot(player)
end

function DataDebugService.saveNow(self: typeof(DataDebugService), player: Player)
	local ok, message = SaveSlotService:savePlayerNow(player)
	print(`[DataDebugService] Force save for {player.Name}: {message}`)

	local snapshot = self:getSnapshot(player)
	snapshot.saved = ok
	snapshot.message = message

	return snapshot
end

function DataDebugService.printSnapshot(self: typeof(DataDebugService), player: Player)
	local snapshot = self:getSnapshot(player)
	print(`[DataDebugService] Manual print for {player.Name}: {encodeForPrint(snapshot)}`)
	return snapshot
end

function DataDebugService._notLoaded(_self: typeof(DataDebugService), player: Player)
	print(`[DataDebugService] Ignored request from {player.Name}; no save slot is loaded.`)

	return {
		loaded = false,
		data = nil,
	}
end

return DataDebugService
